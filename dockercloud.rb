require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'tutum'
require 'erb'
require 'logger'
require 'uri'

if !ENV['DOCKERCLOUD_AUTH']
  puts "Nginx doesn't have access to Docker Cloud API - you might want to give an API role to this service for automatic backend reconfiguration"
  exit 1
end

RESTRICT_MODE = (ENV['RESTRICT_MODE'] || :none).to_sym
# Retrieve the node's fqdn.
THIS_NODE = ENV['DOCKERCLOUD_NODE_FQDN']

$stdout.sync = true
CLIENT_URL = URI.escape("wss://ws.cloud.docker.com/api/audit/v1/events")

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

# PATCH
class TutumApi
  def url(path)
    'https://cloud.docker.com/api/app/v1' + path
  end
end


class NginxConf

  TEMPLATE = File.open("./nginx.conf.erb", "r").read

  def initialize()
    @renderer = ERB.new(TEMPLATE)
  end

  def write(services, file)
    @services = services

    @services.each do |service|
      LOGGER.info service.name + ': ' + service.container_ips.inspect
    end

    result = @renderer.result(binding) #rescue nil
    if result
      File.open(file, "w+") do |f|
        f.write(result)
      end
    end
  end

end


class Container
  attr_reader :id, :attributes

  def initialize(attributes)
    @id = attributes['uuid']
    @attributes = attributes
  end

  def ip
    attributes['private_ip']
  end

  def host
    attributes['container_envvars'].find {|e| e['key'] == 'VIRTUAL_HOST' }['value']
  end

  def port
    attributes['container_envvars'].find {|e| e['key'] == 'VIRTUAL_PORT' }['value'] rescue '80'
  end

  def ssl?
    !!attributes['container_envvars'].find {|e| e['key'] == 'FORCE_SSL' }['value']
  end

  def node
    attributes['container_envvars'].find {|e| e['key'] == 'DOCKERCLOUD_NODE_FQDN'}['value']
  end

  def client_max_body_size
    attributes['container_envvars'].find {|e| e['key'] == 'NGINX_CLIENT_MAX_BODY_SIZE'}['value'] || '1m'
  end

  def running?
    ['Starting', 'Running'].include?(attributes['state'])
  end

end

class Service
  attr_reader :id, :attributes, :session
  def initialize(attributes, session)
    @id = attributes['uuid']
    @attributes = attributes
    @session = session
  end

  def name
    attributes['name']
  end

  def port_types
    @port_types ||= attributes['container_ports'].map {|p| p['port_name']}
  end

  def container_ips
    @container_ips ||= containers.map {|c| c.ip if running? }.sort
  end

  def include?(mode, mode_options = {})
    @mode, @mode_options = mode, mode_options
    reload!
    http? && running? && containers?
  end

  def http?
    (port_types & ['http', 'https']).count > 0
  end

  def host
    @host ||= containers.first.host rescue nil
  end

  def ssl?
    @ssl ||= containers.first.ssl? rescue nil
  end

  def client_max_body_size
    @client_max_body_size ||= containers.first.client_max_body_size rescue "1m"
  end

  def running?
    @state ||= begin
      ['Running', 'Partly running'].include?(attributes['state'])
    end
  end

  def containers?
    containers.count > 0
  end

  def containers
    @containers ||= begin
      attributes['containers'].map do |container_url|
        id = container_url.split("/").last
        container = Container.new(session.containers.get(id))
        if include_container? container
          container
        else
          nil
        end
      end.compact
    end
  end

  def reload!
    @attributes = session.services.get(id)
  end

  def include_container?(container)
    case @mode
    when :node
      @mode_options[:node] == container.node
    when :region
      @mode_options[:region_map][@mode_options[:node]] == @mode_options[:region_map][container.node]
    else
      true
    end
  end

end

class HttpServices

  def self.reload!
    LOGGER.info 'Reloding Nginx...'
    EventMachine.system("nginx -s reload")
  end

  attr_reader :session, :mode, :node
  def initialize(tutum_auth, mode = :none, node = nil)
    begin
      @session = Tutum.new(tutum_auth: tutum_auth)
      @mode = mode
      @node = node
      @services = get_services
    rescue RestClient::RequestFailed => e
      LOGGER.info e.response
      EventMachine::Timer.new(10) do
        HttpServices.new(tutum_auth, @mode, @node).write_conf(ENV['NGINX_DEFAULT_CONF'])
      end
    end
  end

  def write_conf(file_path)
    if @services
      @nginx_conf ||= NginxConf.new()
      @nginx_conf.write(@services, file_path)
      LOGGER.info 'Writing new nginx config'
    end
    self
  end

  private

  def get_services
    services = []
    services_list.each do |service|
      if service.include? mode, node: node, region_map: region_map
        services << service
      end
    end
    services
  end

  def services_list(filters = {})
    session.services.list(filters)['objects'].map {|data| Service.new(data, session) }
  end

  def get_nodes(filters = {})
    session.nodes.list(filters)['objects']
  end

  def region_map
    @region_map ||= begin
      if mode == :region
        get_nodes.map {
            # Map the fqdn to the region. For 'own nodes', region is nil.
            |node| { node['external_fqdn'] => node['region'] }
        }.reduce({}) {
            |h,pairs| pairs.each {|k,v| h[k] = v }; h
        }
      else
        {}
      end
    end
  end

end

module NginxConfHandler
  def file_modified
    @timer ||= EventMachine::Timer.new(0)
    @timer.cancel
    @timer = EventMachine::Timer.new(3) do
      HttpServices.reload!
    end
  end
end

EventMachine.kqueue = true if EventMachine.kqueue?

EM.run {
  @services_changing = []
  @services_changed = false
  @shutting_down = false
  @timer = EventMachine::Timer.new(0)

  def init_nginx_config
    LOGGER.info 'Init Nginx config'
    LOGGER.info 'Restriction mode: ' + RESTRICT_MODE.to_s
    HttpServices.new(ENV['DOCKERCLOUD_AUTH'], RESTRICT_MODE, THIS_NODE).write_conf(ENV['NGINX_DEFAULT_CONF'])
    HttpServices.reload!
  end

  def signal_handler(signal)
    # In rare cases the signal comes multiple times. If we're already shutting down ignore this.
    unless @shutting_down
      # We can't use the logger inside a trap, stdout must be enough.
      puts "Signal #{signal} received. Shutting down."

      @shutting_down = true

      EventMachine.stop
    end
  end

  def connection
    LOGGER.info "Connecting to #{CLIENT_URL}"
    ws = Faye::WebSocket::Client.new(CLIENT_URL, nil, ping: 240, headers: { 'Authorization' => ENV['DOCKERCLOUD_AUTH']})

    ws.on :open do |event|
      LOGGER.info "Connected!"
      if @services_changing.count > 0
        @services_changing = []
        @services_changed = false
        @timer.cancel
        @timer = EventMachine::Timer.new(0)
        init_nginx_config
      end
    end

    ws.on :message do |event|
      data = JSON.parse(event.data)

      if data['type'] == 'service'

        case data['state']
        when 'Scaling', 'Redeploying', 'Stopping', 'Starting', 'Terminating'
          LOGGER.info "Service: #{data['uuid']} is #{data['state']}..."
          @timer.cancel # cancel any conf writes
          @services_changing << data['uuid']
        when 'Running', 'Stopped', 'Not running', 'Terminated'
          if @services_changing.count > 0
            LOGGER.info "Service: #{data['uuid']} is #{data['state']}!"
            @services_changing.shift
            @timer.cancel # cancel any conf writes
            @services_changed = true
          end
        end

        if @services_changed && @services_changing == []
          LOGGER.info "Services changed - Rewrite Nginx config"
          @services_changed = false
          @timer.cancel
          @timer = EventMachine::Timer.new(5) do
            HttpServices.new(ENV['DOCKERCLOUD_AUTH'], RESTRICT_MODE, THIS_NODE).write_conf(ENV['NGINX_DEFAULT_CONF'])
          end
        end

      end
    end

    ws.on(:error) do |event|
      LOGGER.info JSON.parse(event.data).inspect
    end

    ws.on(:close) do |event|
      unless @shutting_down
        LOGGER.info 'Connection closed! ... Restarting connection'

        # restart the connection
        connection
      else
        LOGGER.info 'Connection closed!'
      end
    end

  end

  init_nginx_config
  Signal.trap('INT')  { signal_handler('INT') }
  Signal.trap('TERM') { signal_handler('TERM') }
  EventMachine.watch_file(ENV['NGINX_DEFAULT_CONF'], NginxConfHandler)
  connection
}

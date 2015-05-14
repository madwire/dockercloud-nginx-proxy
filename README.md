# tutum-nginx-proxy

tutum-nginx-proxy sets up a container running nginx and, when launched in Tutum, will automatically reconfigures itself when any web service has finished Scaling, Redeploying, Starting, Stopping or Terminating. The best part is that any web service that has a VIRTUAL_HOST Environment variable and is listening on port 80 (internally) will automatically be picked up so no need to link containers.

## Usage within Tutum

Launch the web service(s) you want to load-balance using Tutum. During the "Service configuration" step of the wizard, Make sure you "Click to override ports defined in image" and your service must be on port 80 but not published. During the "Environment variables" step of the wizard, Add a VIRTUAL_HOST variable with the domain name you desire. `VIRTUAL_HOST="example.com"`

Then, launch the load balancer. To do this, select "Public images", and search for madwire/tutum-nginx-proxy. Add "Full Access" API role (this will allow nginx to be updated dynamically by querying Tutum's API).

That's it - the proxy container will start querying Tutum's API for an updated list of services and reconfigure itself automatically. You can repeat step one and new services will be automatically added too.

## Configuration

These are the environment variables you add to web services you want to load-balance:

- VIRTUAL_HOST: Domain host name, leave a space for multiple domains. e.g. `www.example.com example.com`
- FORCE_SSL: Optional. This will use a self-signed cert and redirect traffic to https, its perfect when married to external services like [cloudflare](https://www.cloudflare.com/)

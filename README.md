# dockercloud-nginx-proxy

dockercloud-nginx-proxy sets up a container running nginx and, when launched in Docker Cloud, will automatically reconfigures itself when any web service has finished Scaling, Redeploying, Starting, Stopping or Terminating. The best part is that any web service that has a VIRTUAL_HOST Environment variable and is listening on port 80 (internally) will automatically be picked up so no need to link containers.

## Usage within Docker Cloud

Launch the web service(s) you want to load-balance using Docker Cloud. During the "Service configuration" step of the wizard, Make sure you "Click to override ports defined in image" and your service must be on port 80 but not published. During the "Environment variables" step of the wizard, Add a VIRTUAL_HOST variable with the domain name you desire. `VIRTUAL_HOST="example.com"`

Then, launch the load balancer. To do this, select "Public images", and search for madwire/dockercloud-nginx-proxy. Add "Full Access" API role (this will allow nginx to be updated dynamically by querying Docker Cloud's API).

That's it - the proxy container will start querying Docker Cloud's API for an updated list of services and reconfigure itself automatically. You can repeat step one and new services will be automatically added too.

## Configuration

These are the environment variables you add to web services you want to load-balance:

- VIRTUAL_HOST: Domain host name, leave a space for multiple domains. e.g. `www.example.com example.com`
- FORCE_SSL: Optional. This will use a self-signed cert and redirect traffic to https, its perfect when married to external services like [cloudflare](https://www.cloudflare.com/)

These are the environment variables you can add to the load-balance:

- RESTRICT_MODE: Optional. Restricts upstream containers. You have the choice between the following modes:
    - **node**: Only use containers that are on the same node as upstream.
    - **region**: Only use containers that are in the same region as upstream. e.g. "digitalocean frankfurt 1"
    - **none**: Does exactly what you think it does.

## LICENSE

The MIT License (MIT)

Copyright (c) 2015 Richard Adams

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

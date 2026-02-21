# Testing an ONVIF Client with onvif_simple_server

This guide walks through setting up `onvif_simple_server` on macOS as a mock ONVIF device to test any ONVIF-compatible client (Onvif Device Manager, Synology, Frigate, Onvier, etc.).

## Prerequisites

Install the required dependencies via Homebrew:

```sh
brew install lighttpd libtomcrypt json-c
```

Build the three binaries:

```sh
make clean && make
```

## Overview of Components

| Binary | Role | How it runs |
|--------|------|-------------|
| `onvif_simple_server` | Handles all ONVIF SOAP requests | As a CGI script under an HTTP server |
| `onvif_notify_server` | Manages event subscriptions and push/pull notifications | Standalone daemon |
| `wsd_simple_server` | WS-Discovery — lets ONVIF clients auto-discover the device on LAN | Standalone daemon |

## Step 1 — Create the Configuration File

Copy the example config and edit it:

```sh
sudo mkdir -p /etc
sudo cp onvif_simple_server.conf.example /etc/onvif_simple_server.conf
sudo nano /etc/onvif_simple_server.conf
```

Minimal settings to change for macOS testing:

```ini
model=TestCamera
manufacturer=TestVendor
firmware_ver=1.0.0
hardware_id=TEST01
serial_num=SN0000000001
ifs=en0          # use your macOS interface: en0 (Wi-Fi) or en5 (USB LAN)
port=8080        # must match your HTTP server port
scope=onvif://www.onvif.org/Profile/Streaming

# Disable auth for initial testing (uncomment to enable later)
#user=admin
#password=admin

adv_enable_media2=0
adv_fault_if_unknown=0
adv_fault_if_set=0
adv_synology_nvr=0

# Profile 0 — point url at any real or fake RTSP source
name=Profile_0
width=1920
height=1080
url=rtsp://%s/stream0
snapurl=http://%s:8080/snapshot.jpg
type=H264
audio_encoder=NONE
audio_decoder=NONE

# Disable PTZ for simple testing
ptz=0

# Disable events for simple testing
events=0
```

Find your active interface name:

```sh
ifconfig | grep 'inet ' | grep -v '127.0.0.1'
# Typical macOS: en0 (Wi-Fi), en5 or en7 (USB Ethernet)
```

## Step 2 — Set Up the CGI Directory Structure

The HTTP server serves `onvif_simple_server` as a CGI binary. Create the web root:

```sh
sudo mkdir -p /usr/local/www/onvif
sudo cp onvif_simple_server /usr/local/www/onvif/
cd /usr/local/www/onvif

# Create symlinks so each ONVIF service endpoint resolves to the same binary
sudo ln -sf ./onvif_simple_server device_service
sudo ln -sf ./onvif_simple_server events_service
sudo ln -sf ./onvif_simple_server media_service
sudo ln -sf ./onvif_simple_server media2_service
sudo ln -sf ./onvif_simple_server ptz_service
sudo ln -sf ./onvif_simple_server deviceio_service

# Copy XML response templates
cd /Users/anatol/sources/onvif_simple_server   # adjust to your source path
sudo cp -R device_service_files   /usr/local/www/onvif/
sudo cp -R events_service_files   /usr/local/www/onvif/
sudo cp -R generic_files          /usr/local/www/onvif/
sudo cp -R media_service_files    /usr/local/www/onvif/
sudo cp -R media2_service_files   /usr/local/www/onvif/
sudo cp -R ptz_service_files      /usr/local/www/onvif/
sudo cp -R deviceio_service_files /usr/local/www/onvif/
```

## Step 3 — Configure lighttpd

Create `/usr/local/etc/lighttpd-onvif.conf`:

```conf
server.document-root = "/usr/local/www/"
server.port           = 8080
server.modules        = ( "mod_cgi" )

# Tell lighttpd to execute files ending in _service as CGI
cgi.assign = ( "_service" => "" )
```

Start lighttpd in the foreground for easy debugging:

```sh
lighttpd -D -f /usr/local/etc/lighttpd-onvif.conf
```

Or in the background:

```sh
lighttpd -f /usr/local/etc/lighttpd-onvif.conf
```

## Step 4 — Verify the ONVIF Server Responds

Test the device service endpoint with curl:

```sh
curl -s -X POST http://127.0.0.1:8080/onvif/device_service \
  -H "Content-Type: application/soap+xml" \
  -d '<?xml version="1.0"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <tds:GetSystemDateAndTime xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>
  </s:Body>
</s:Envelope>'
```

You should receive an XML response containing the current date/time.

## Step 5 — Start the Notification Daemon (Optional)

Required only if you want to test ONVIF events (motion alarms, etc.):

```sh
# Create the directory that onvif_notify_server monitors for event files
mkdir -p /tmp/onvif_notify_server

# Install the notification templates
sudo mkdir -p /etc/onvif_notify_server
sudo cp notify_files/* /etc/onvif_notify_server/

# Update the config to enable events (edit /etc/onvif_simple_server.conf):
#   events=3          (1=PullPoint, 2=BaseSubscription, 3=both)
#   topic=tns1:VideoSource/MotionAlarm
#   source_name=Source
#   source_type=tt:ReferenceToken
#   source_value=VideoSourceToken
#   input_file=/tmp/onvif_notify_server/motion_alarm

# Run in the foreground with debug output:
./onvif_notify_server -f -d 5 -c /etc/onvif_simple_server.conf
```

### Triggering Events

Once a client has subscribed, simulate events by creating/removing files:

```sh
# Fire a motion alarm ON
touch /tmp/onvif_notify_server/motion_alarm

# Fire a motion alarm OFF
rm /tmp/onvif_notify_server/motion_alarm
```

The notify server detects file creation/deletion and sends the appropriate ONVIF notification to all subscribers.

## Step 6 — Start WS-Discovery (Optional)

Required only if you want ONVIF clients to auto-discover the device on the LAN
(most clients also support manual IP entry, which avoids needing this):

```sh
# Install the WSD templates
sudo mkdir -p /etc/wsd_simple_server
sudo cp wsd_files/* /etc/wsd_simple_server/

# Replace en0 and YOUR_IP with your actual interface and IP
./wsd_simple_server -f -d 5 \
  -i en0 \
  -x "http://YOUR_IP:8080/onvif/device_service" \
  -m TestCamera \
  -n TestVendor \
  -p /tmp/wsd_simple_server.pid
```

## Step 7 — Connect an ONVIF Client

### Onvif Device Manager (Windows)
1. Click **Add** → enter `http://YOUR_IP:8080/onvif/device_service`
2. Leave username/password blank (if auth is disabled in config)
3. Click **Connect**

### Frigate NVR
Add to `frigate.yml`:
```yaml
cameras:
  test_cam:
    onvif:
      host: YOUR_IP
      port: 8080
      user: ""
      password: ""
```

### Onvier / other Android clients
Enter the device URL: `http://YOUR_IP:8080/onvif/device_service`

## Debugging Tips

### Enable verbose logging

Run `onvif_simple_server` directly as CGI with debug output:

```sh
# Simulate a CGI call manually (lighttpd not needed)
REQUEST_METHOD=POST \
CONTENT_TYPE="application/soap+xml" \
CONTENT_LENGTH=200 \
./onvif/device_service <<'EOF'
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <tds:GetSystemDateAndTime xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>
  </s:Body>
</s:Envelope>
EOF
```

Run daemons with maximum debug level:

```sh
./onvif_notify_server -f -d 5 -c /etc/onvif_simple_server.conf
./wsd_simple_server   -f -d 5 -i en0 -x "http://YOUR_IP:8080/onvif/device_service" -p /tmp/wsd.pid
```

### Common issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `GetCapabilities` returns fault | Templates not found | Verify all `*_service_files/` dirs are in the CGI working directory (same dir as the binary) |
| Client can't authenticate | Config has `user=` set | Either clear it or pass the right credentials |
| Discovery not working | WSD not running or firewall | Start `wsd_simple_server`; check that UDP port 3702 is open |
| Events never fire | `events=0` in config | Set `events=3` and restart `onvif_notify_server` |
| `ifs` not found | Wrong interface name | Run `ifconfig` and use the interface with your LAN IP |
| `adv_fault_if_unknown=1` | Some clients need this | Set it in config if client fails to connect |

### Checking the working directory

`onvif_simple_server` looks for template files relative to its own location.
When run via lighttpd CGI the working directory is the directory containing the CGI binary.
If templates are missing you will see errors in lighttpd's error log.

```sh
# Confirm templates are co-located with the binary
ls /usr/local/www/onvif/device_service_files/
```

## Quick-Start Summary

```sh
# 1. Build
make clean && make

# 2. Deploy
sudo mkdir -p /usr/local/www/onvif /etc/onvif_notify_server /etc/wsd_simple_server
sudo cp onvif_simple_server /usr/local/www/onvif/
for svc in device events media media2 ptz deviceio; do
    sudo ln -sf ./onvif_simple_server /usr/local/www/onvif/${svc}_service
done
sudo cp -R {device,events,generic,media,media2,ptz,deviceio}_service_files /usr/local/www/onvif/ 2>/dev/null; sudo cp -R generic_files /usr/local/www/onvif/
sudo cp notify_files/* /etc/onvif_notify_server/
sudo cp onvif_simple_server.conf.example /etc/onvif_simple_server.conf
# Edit /etc/onvif_simple_server.conf: set ifs= and port=8080

# 3. Start HTTP server
lighttpd -f /usr/local/etc/lighttpd-onvif.conf

# 4. (Optional) Start event daemon
mkdir -p /tmp/onvif_notify_server
./onvif_notify_server -f -d 3 -c /etc/onvif_simple_server.conf &

# 5. Test
curl -s http://127.0.0.1:8080/onvif/device_service -X POST \
  -H "Content-Type: application/soap+xml" \
  -d '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><tds:GetSystemDateAndTime xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/></s:Body></s:Envelope>'
```

# Dead DFIR
Mount forensic disk images and perform baselining and post-mortem analysis on Linux machines. 

### Use
Prior to executing the `baseline.sh` script.

```bash
sudo ./baseline.sh -m <image_file> /mnt/<mount_point> <time_zone>
```

### Example Usage
```bash
sudo ./baseline.sh /mnt/web_server
sudo ./baseline.sh /mnt/web_server UTC
sudo ./baseline.sh -m Webserver.E01 /mnt/web_server
sudo ./baseline.sh -m Webserver.E01 /mnt/web_server UTC
```

- `/mnt/<mount_point>` - Specify the target filesystem location that has been mounted from a dead disk image.
- `<time_zone>` - Specify a timezone for command based output (log based output will still be in the timezone of the target machine). By default this is set to the same as the target machine.
- `-m <image_file>` - Specify an image file format (.E01, .dd, .img) to automatically mount to the mountpoint specified in `/mnt/<mount_point

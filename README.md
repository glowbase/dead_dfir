# Dead DFIR
Baseline and perform analysis on dead Linux machine mounted via image file.

### Use
Prior to executing the `baseline.sh` script, ensure you have already mounted the target file system. 

```bash
sudo ./baseline.sh /mnt/<drive> <time_zone>
```

- `/mnt<drive>` - Specify the target filesystem location that has been mounted from a dead disk image.
- `<time_zone>` - Specify a timezone for command based output (log based output will still be in the timezone of the target machine). By default this is set to the same as the target machine.

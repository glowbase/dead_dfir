# Dead DFIR
Baseline and perform analysis on dead Linux machine mounted via image file.

### Use
Prior to executing the `baseline.sh` script, ensure you have already mounted the target file system. 

```bash
sudo ./baseline.sh /mnt/<drive>
```

### To Do:
- [x] Device Settings (OS, Kernel, Processor, Time Zone, Last Shutdown)
- [x] Users (Username, UID, Groups, Shell)
- [x] Sudoers (Look in `/etc/sudoers.d`)
- [x] Installed Software (Install Date, Name, Version)
- [x] Persistence Mechanisms (Cron)
- [x] Network Configuration
- [ ] System Logs (Detect Anomalous Behavior)
- [ ] Web Server (Configuration, Logs)
- [ ] Database Server (Configuration, Logs)
- [x] User Profiles
- [x] User CLI History (Bash, Zsh)
- [ ] Last Modified Files

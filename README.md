# Dead DFIR
Baseline dead Unix machines via mounted image.

### Use
Prior to executing the `baseline.sh` script, ensure you have already mounted the target file system. 

```bash
sudo ./baseline.sh /mnt/<drive>
```

### To Do:
- [ ] Device Settings (OS, Kernel, Processor, Time Zone, Last Shutdown)
- [ ] Users (Username, UID, Groups, Shell)
- [ ] Sudoers (Look in `/etc/sudoers.d`)
- [ ] Installed Software (Install Date, Name, Version)
- [ ] Persistence Mechanisms (Cron)
- [ ] Network Configuration
- [ ] System Logs (Detect Anomalous Behavior)
- [ ] Web Server (Configuration, Logs)
- [ ] Database Server (Configuration, Logs)
- [ ] User Profiles
- [ ] User CLI History (Bash, Zsh)
- [ ] Last Modified Files

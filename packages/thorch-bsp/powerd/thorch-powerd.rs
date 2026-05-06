use std::collections::HashMap;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::{self, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const EV_KEY: u16 = 1;
const EV_SW: u16 = 5;
const KEY_POWER: u16 = 116;
const SW_LID: u16 = 0;
const EVIOCGRAB: usize = 0x40044590;
const POLLIN: i16 = 0x0001;

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

#[link(name = "c")]
extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
    fn ioctl(fd: i32, request: usize, ...) -> i32;
}

#[derive(Clone)]
struct Config {
    state_dir: PathBuf,
    sysfs_root: PathBuf,
    input_root: PathBuf,
    event_root: PathBuf,
    shutdown_delay: u64,
    park_cores: bool,
    backlight_power: String,
}

impl Config {
    fn load() -> Self {
        let file_values = read_config_file(Path::new("/etc/thorch/powerd.conf"));
        let value = |name: &str, default: &str| {
            env::var(name)
                .ok()
                .or_else(|| file_values.get(name).cloned())
                .unwrap_or_else(|| default.to_string())
        };

        Self {
            state_dir: PathBuf::from(value("THORCH_POWERD_STATE_DIR", "/run/thorch-powerd")),
            sysfs_root: PathBuf::from(value("THORCH_POWERD_SYSFS_ROOT", "/sys")),
            input_root: PathBuf::from(value("THORCH_POWERD_INPUT_ROOT", "/sys/class/input")),
            event_root: PathBuf::from(value("THORCH_POWERD_EVENT_ROOT", "/dev/input")),
            shutdown_delay: value("THORCH_POWERD_SHUTDOWN_DELAY", "900")
                .parse()
                .unwrap_or(900),
            park_cores: value("THORCH_POWERD_PARK_CORES", "0") == "1",
            backlight_power: value("THORCH_POWERD_BACKLIGHT_POWER", "4"),
        }
    }

    fn active_flag(&self) -> PathBuf {
        self.state_dir.join("active")
    }

    fn sys(&self, suffix: &str) -> PathBuf {
        self.sysfs_root.join(suffix.trim_start_matches('/'))
    }
}

struct OpenedDevice {
    file: File,
}

fn read_config_file(path: &Path) -> HashMap<String, String> {
    let mut values = HashMap::new();
    let Ok(text) = fs::read_to_string(path) else {
        return values;
    };

    for line in text.lines() {
        let line = line.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        values.insert(key.trim().to_string(), value.trim().trim_matches('"').trim_matches('\'').to_string());
    }
    values
}

fn write_text(path: &Path, value: &str) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    file.write_all(value.as_bytes())?;
    file.write_all(b"\n")
}

fn read_text(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|value| value.trim().to_string())
}

fn append_line(path: &Path, line: &str) {
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{line}");
    }
}

fn run(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn run_capture(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program).args(args).output().ok()?;
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn log(message: &str) {
    eprintln!("thorch-powerd: {message}");
}

fn input_devices(config: &Config, names: &[&str]) -> Vec<PathBuf> {
    let mut devices = Vec::new();
    let Ok(entries) = fs::read_dir(&config.input_root) else {
        return devices;
    };
    let mut entries: Vec<_> = entries.filter_map(Result::ok).collect();
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with("event") {
            continue;
        }
        let device_name = read_text(&entry.path().join("device/name")).unwrap_or_default();
        if names.is_empty() || names.iter().any(|wanted| *wanted == device_name) {
            devices.push(config.event_root.join(name));
        }
    }
    devices
}

fn set_grab(file: &File, enabled: bool) {
    let value: i32 = if enabled { 1 } else { 0 };
    unsafe {
        ioctl(file.as_raw_fd(), EVIOCGRAB, &value);
    }
}

fn read_event(file: &mut File) -> io::Result<(u16, u16, i32)> {
    let mut buf = [0u8; 24];
    file.read_exact(&mut buf)?;
    let event_type = u16::from_ne_bytes([buf[16], buf[17]]);
    let code = u16::from_ne_bytes([buf[18], buf[19]]);
    let value = i32::from_ne_bytes([buf[20], buf[21], buf[22], buf[23]]);
    Ok((event_type, code, value))
}

fn thorch_user() -> String {
    let mut candidates = Vec::new();
    if let Ok(entries) = fs::read_dir("/etc/sddm.conf.d") {
        for entry in entries.filter_map(Result::ok) {
            candidates.push(entry.path());
        }
    }
    candidates.push(PathBuf::from("/etc/sddm.conf"));

    for path in candidates {
        let Ok(text) = fs::read_to_string(path) else {
            continue;
        };
        let mut autologin = false;
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('[') {
                autologin = line == "[Autologin]";
                continue;
            }
            if autologin {
                if let Some((key, value)) = line.split_once('=') {
                    if key.trim() == "User" {
                        return value.trim().to_string();
                    }
                }
            }
        }
    }

    "thorch".to_string()
}

fn passwd_home(user: &str) -> Option<String> {
    let text = fs::read_to_string("/etc/passwd").ok()?;
    for line in text.lines() {
        let parts: Vec<_> = line.split(':').collect();
        if parts.len() >= 6 && parts[0] == user {
            return Some(parts[5].to_string());
        }
    }
    None
}

fn run_as_user(program: &str, args: &[&str]) -> Option<String> {
    let user = thorch_user();
    let home = passwd_home(&user)?;
    let uid = run_capture("id", &["-u", &user])?;
    let output = Command::new("runuser")
        .arg("-u")
        .arg(&user)
        .arg("--")
        .arg("env")
        .arg(format!("HOME={home}"))
        .arg(format!("XDG_RUNTIME_DIR=/run/user/{uid}"))
        .arg(format!("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"))
        .arg(program)
        .args(args)
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn save_backlights_and_blank(config: &Config) {
    let state = config.state_dir.join("backlights");
    let _ = fs::write(&state, "");
    let root = config.sys("class/backlight");
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };

    for entry in entries.filter_map(Result::ok) {
        let dev = entry.path();
        if !dev.is_dir() {
            continue;
        }
        let brightness = read_text(&dev.join("brightness")).unwrap_or_default();
        let bl_power = read_text(&dev.join("bl_power")).unwrap_or_default();
        append_line(&state, &format!("{}|{}|{}", dev.display(), brightness, bl_power));
        if write_text(&dev.join("bl_power"), &config.backlight_power).is_err() {
            let _ = write_text(&dev.join("brightness"), "0");
        }
    }
}

fn restore_backlights(config: &Config) {
    let Ok(text) = fs::read_to_string(config.state_dir.join("backlights")) else {
        return;
    };
    for line in text.lines() {
        let parts: Vec<_> = line.split('|').collect();
        if parts.len() < 3 {
            continue;
        }
        let dev = PathBuf::from(parts[0]);
        if !dev.is_dir() {
            continue;
        }
        let _ = write_text(&dev.join("bl_power"), "0");
        if !parts[1].is_empty() {
            let _ = write_text(&dev.join("brightness"), parts[1]);
        }
        let _ = write_text(&dev.join("bl_power"), "0");
    }
}

fn mute_audio(config: &Config) {
    let muted = run_as_user("pactl", &["get-sink-mute", "@DEFAULT_SINK@"])
        .and_then(|out| out.split_whitespace().nth(1).map(str::to_string))
        .unwrap_or_else(|| "unknown".to_string());
    let _ = fs::write(config.state_dir.join("audio-muted"), muted);
    let _ = run_as_user("pactl", &["set-sink-mute", "@DEFAULT_SINK@", "true"]);
}

fn restore_audio(config: &Config) {
    match read_text(&config.state_dir.join("audio-muted")).as_deref() {
        Some("yes" | "true") => {
            let _ = run_as_user("pactl", &["set-sink-mute", "@DEFAULT_SINK@", "true"]);
        }
        Some("no" | "false") => {
            let _ = run_as_user("pactl", &["set-sink-mute", "@DEFAULT_SINK@", "false"]);
        }
        _ => {}
    }
}

fn governor_paths(config: &Config) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    let cpufreq = config.sys("devices/system/cpu/cpufreq");
    if let Ok(entries) = fs::read_dir(cpufreq) {
        for entry in entries.filter_map(Result::ok) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("policy") {
                paths.push(entry.path().join("scaling_governor"));
            }
        }
    }
    let devfreq = config.sys("class/devfreq");
    if let Ok(entries) = fs::read_dir(devfreq) {
        for entry in entries.filter_map(Result::ok) {
            paths.push(entry.path().join("governor"));
        }
    }
    paths
}

fn save_governors_and_powersave(config: &Config) {
    let state = config.state_dir.join("governors");
    let _ = fs::write(&state, "");
    for path in governor_paths(config) {
        let current = read_text(&path).unwrap_or_default();
        append_line(&state, &format!("{}|{}", path.display(), current));
        let parent = path.parent().unwrap_or_else(|| Path::new("/"));
        let available = read_text(&parent.join("scaling_available_governors"))
            .or_else(|| read_text(&parent.join("available_governors")))
            .unwrap_or_default();
        if available.split_whitespace().any(|value| value == "powersave") {
            let _ = write_text(&path, "powersave");
        }
    }
}

fn restore_governors(config: &Config) {
    let Ok(text) = fs::read_to_string(config.state_dir.join("governors")) else {
        return;
    };
    for line in text.lines() {
        let Some((path, previous)) = line.split_once('|') else {
            continue;
        };
        if !previous.is_empty() {
            let _ = write_text(Path::new(path), previous);
        }
    }
}

fn disable_rgb(config: &Config) {
    if run("systemctl", &["is-active", "--quiet", "thorch-rgb-battery.service"]) {
        let _ = fs::write(config.state_dir.join("rgb-battery-service-active"), "1\n");
        run("systemctl", &["stop", "thorch-rgb-battery.service"]);
    }
    run("thorch-rgb", &["poweroff"]);
}

fn restore_rgb(config: &Config) {
    run("thorch-rgb", &["apply-config"]);
    if config.state_dir.join("rgb-battery-service-active").exists() {
        run("systemctl", &["restart", "thorch-rgb-battery.service"]);
    }
}

fn park_cores(config: &Config) {
    if !config.park_cores {
        return;
    }
    let state = config.state_dir.join("cores");
    let _ = fs::write(&state, "");
    let root = config.sys("devices/system/cpu");
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with("cpu") || name == "cpu0" {
            continue;
        }
        let online_path = entry.path().join("online");
        let previous = read_text(&online_path).unwrap_or_default();
        append_line(&state, &format!("{}|{}", online_path.display(), previous));
        let _ = write_text(&online_path, "0");
    }
}

fn restore_cores(config: &Config) {
    let Ok(text) = fs::read_to_string(config.state_dir.join("cores")) else {
        return;
    };
    for line in text.lines() {
        let Some((path, previous)) = line.split_once('|') else {
            continue;
        };
        let _ = write_text(Path::new(path), if previous.is_empty() { "1" } else { previous });
    }
}

fn current_exe() -> Option<PathBuf> {
    env::current_exe().ok()
}

fn spawn_self(args: &[&str], config: &Config) -> Option<u32> {
    let exe = current_exe()?;
    Command::new(exe)
        .args(args)
        .env("THORCH_POWERD_STATE_DIR", &config.state_dir)
        .env("THORCH_POWERD_SYSFS_ROOT", &config.sysfs_root)
        .env("THORCH_POWERD_INPUT_ROOT", &config.input_root)
        .env("THORCH_POWERD_EVENT_ROOT", &config.event_root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok()
        .map(|child| child.id())
}

fn block_input(config: &Config) {
    if let Some(pid) = spawn_self(&["input-blocker"], config) {
        let _ = fs::write(config.state_dir.join("input-blocker-pid"), format!("{pid}\n"));
    }
}

fn unblock_input(config: &Config) {
    kill_pid_file(&config.state_dir.join("input-blocker-pid"));
}

fn schedule_shutdown(config: &Config) {
    if config.shutdown_delay == 0 {
        return;
    }
    if let Some(pid) = spawn_self(&["shutdown-watcher"], config) {
        let _ = fs::write(config.state_dir.join("shutdown-pid"), format!("{pid}\n"));
    }
}

fn cancel_shutdown(config: &Config) {
    kill_pid_file(&config.state_dir.join("shutdown-pid"));
}

fn kill_pid_file(path: &Path) {
    let Some(pid) = read_text(path) else {
        return;
    };
    if !pid.is_empty() {
        run("kill", &[pid.as_str()]);
    }
}

fn suspend_fake(config: &Config) {
    if config.active_flag().exists() {
        return;
    }
    let _ = fs::create_dir_all(&config.state_dir);
    let _ = fs::write(config.active_flag(), "");
    log("entering fake suspend");
    save_backlights_and_blank(config);
    mute_audio(config);
    disable_rgb(config);
    save_governors_and_powersave(config);
    park_cores(config);
    block_input(config);
    schedule_shutdown(config);
}

fn resume_fake(config: &Config) {
    if !config.active_flag().exists() {
        return;
    }
    log("leaving fake suspend");
    cancel_shutdown(config);
    unblock_input(config);
    restore_cores(config);
    restore_governors(config);
    restore_audio(config);
    restore_rgb(config);
    restore_backlights(config);
    let _ = fs::remove_dir_all(&config.state_dir);
}

fn status(config: &Config) {
    if config.active_flag().exists() {
        println!("active");
    } else {
        println!("inactive");
    }
}

fn input_blocker(config: &Config) {
    let mut files = Vec::new();
    let devices = input_devices(config, &[]);
    for path in devices {
        let event_name = path.file_name().and_then(|name| name.to_str()).unwrap_or("");
        let name = read_text(&config.input_root.join(event_name).join("device/name")).unwrap_or_default();
        if matches!(name.as_str(), "pmic_pwrkey" | "gpio-keys") {
            continue;
        }
        if let Ok(file) = File::open(path) {
            set_grab(&file, true);
            files.push(file);
        }
    }
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn shutdown_watcher(config: &Config) {
    thread::sleep(Duration::from_secs(config.shutdown_delay));
    if !config.active_flag().exists() {
        return;
    }
    let power_root = config.sys("class/power_supply");
    if let Ok(entries) = fs::read_dir(power_root) {
        for entry in entries.filter_map(Result::ok) {
            if read_text(&entry.path().join("status")).as_deref() == Some("Charging") {
                log("fake suspend timeout reached while charging; leaving system on");
                return;
            }
        }
    }
    log("fake suspend timeout reached; powering off");
    run("systemctl", &["poweroff"]);
}

fn daemon(config: &Config) {
    let mut last_power = Instant::now()
        .checked_sub(Duration::from_secs(10))
        .unwrap_or_else(Instant::now);
    loop {
        let mut devices = HashMap::new();
        for path in input_devices(config, &["pmic_pwrkey", "gpio-keys"]) {
            if let Ok(file) = File::open(path) {
                devices.insert(file.as_raw_fd(), OpenedDevice { file });
            }
        }

        if devices.is_empty() {
            thread::sleep(Duration::from_secs(1));
            continue;
        }

        let mut disconnected = false;
        while !disconnected {
            let mut poll_fds: Vec<PollFd> = devices
                .keys()
                .map(|fd| PollFd {
                    fd: *fd,
                    events: POLLIN,
                    revents: 0,
                })
                .collect();
            let poll_result = unsafe { poll(poll_fds.as_mut_ptr(), poll_fds.len(), 1000) };
            if poll_result < 0 {
                break;
            }
            for poll_fd in poll_fds.iter().filter(|fd| fd.revents & POLLIN != 0) {
                let Some(opened) = devices.get_mut(&poll_fd.fd) else {
                    continue;
                };
                let (event_type, code, value) = match read_event(&mut opened.file) {
                    Ok(event) => event,
                    Err(_) => {
                        disconnected = true;
                        break;
                    }
                };
                if event_type == EV_KEY && code == KEY_POWER && value == 1 {
                    let now = Instant::now();
                    if now.duration_since(last_power) >= Duration::from_millis(400) {
                        last_power = now;
                        if config.active_flag().exists() {
                            resume_fake(config);
                        } else {
                            suspend_fake(config);
                        }
                    }
                } else if event_type == EV_SW && code == SW_LID {
                    if value == 1 {
                        suspend_fake(config);
                    } else {
                        resume_fake(config);
                    }
                }
            }
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn usage() -> ! {
    eprintln!("usage: thorch-powerd [daemon|toggle|suspend|resume|status|input-blocker|shutdown-watcher]");
    process::exit(2);
}

fn main() {
    let config = Config::load();
    let action = env::args().nth(1).unwrap_or_else(|| "daemon".to_string());

    match action.as_str() {
        "daemon" => daemon(&config),
        "toggle" => {
            if config.active_flag().exists() {
                resume_fake(&config);
            } else {
                suspend_fake(&config);
            }
        }
        "suspend" => suspend_fake(&config),
        "resume" => resume_fake(&config),
        "status" => status(&config),
        "input-blocker" => input_blocker(&config),
        "shutdown-watcher" => shutdown_watcher(&config),
        _ => usage(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_root(name: &str) -> PathBuf {
        let mut path = env::temp_dir();
        path.push(format!(
            "thorch-powerd-test-{}-{}",
            std::process::id(),
            name
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn write(path: &Path, value: &str) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, value).unwrap();
    }

    fn config(root: &Path) -> Config {
        Config {
            state_dir: root.join("state"),
            sysfs_root: root.join("sys"),
            input_root: root.join("sys/class/input"),
            event_root: root.join("dev/input"),
            shutdown_delay: 0,
            park_cores: true,
            backlight_power: "4".to_string(),
        }
    }

    #[test]
    fn read_config_file_handles_comments_quotes_and_whitespace() {
        let root = test_root("config");
        let path = root.join("powerd.conf");
        write(
            &path,
            r#"
              # ignored
              THORCH_POWERD_SHUTDOWN_DELAY = "120" # trailing
              THORCH_POWERD_PARK_CORES='1'
              malformed
            "#,
        );

        let values = read_config_file(&path);
        assert_eq!(
            values.get("THORCH_POWERD_SHUTDOWN_DELAY").map(String::as_str),
            Some("120")
        );
        assert_eq!(
            values.get("THORCH_POWERD_PARK_CORES").map(String::as_str),
            Some("1")
        );
        assert!(!values.contains_key("malformed"));

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn input_devices_can_filter_or_return_all_event_devices() {
        let root = test_root("input-devices");
        let cfg = config(&root);
        write(&cfg.input_root.join("event2/device/name"), "gamepad\n");
        write(&cfg.input_root.join("event0/device/name"), "pmic_pwrkey\n");
        write(&cfg.input_root.join("mouse0/device/name"), "gamepad\n");
        write(&cfg.input_root.join("event1/device/name"), "gpio-keys\n");
        fs::create_dir_all(&cfg.event_root).unwrap();

        assert_eq!(
            input_devices(&cfg, &["gpio-keys"]),
            vec![cfg.event_root.join("event1")]
        );
        assert_eq!(
            input_devices(&cfg, &[]),
            vec![
                cfg.event_root.join("event0"),
                cfg.event_root.join("event1"),
                cfg.event_root.join("event2"),
            ]
        );

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn save_and_restore_backlights_round_trips_brightness_and_unblanks() {
        let root = test_root("backlights");
        let cfg = config(&root);
        let panel = cfg.sys("class/backlight/panel0");
        write(&panel.join("brightness"), "80\n");
        write(&panel.join("bl_power"), "0\n");
        fs::create_dir_all(&cfg.state_dir).unwrap();

        save_backlights_and_blank(&cfg);
        assert_eq!(read_text(&panel.join("bl_power")).as_deref(), Some("4"));

        write(&panel.join("brightness"), "1\n");
        write(&panel.join("bl_power"), "4\n");
        restore_backlights(&cfg);

        assert_eq!(read_text(&panel.join("brightness")).as_deref(), Some("80"));
        assert_eq!(read_text(&panel.join("bl_power")).as_deref(), Some("0"));

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn save_and_restore_governors_only_uses_powersave_when_available() {
        let root = test_root("governors");
        let cfg = config(&root);
        let cpu = cfg.sys("devices/system/cpu/cpufreq/policy0");
        let gpu = cfg.sys("class/devfreq/gpu0");
        let mem = cfg.sys("class/devfreq/mem0");
        write(&cpu.join("scaling_governor"), "schedutil\n");
        write(&cpu.join("scaling_available_governors"), "performance schedutil powersave\n");
        write(&gpu.join("governor"), "performance\n");
        write(&gpu.join("available_governors"), "performance powersave\n");
        write(&mem.join("governor"), "performance\n");
        write(&mem.join("available_governors"), "performance\n");
        fs::create_dir_all(&cfg.state_dir).unwrap();

        save_governors_and_powersave(&cfg);
        assert_eq!(read_text(&cpu.join("scaling_governor")).as_deref(), Some("powersave"));
        assert_eq!(read_text(&gpu.join("governor")).as_deref(), Some("powersave"));
        assert_eq!(read_text(&mem.join("governor")).as_deref(), Some("performance"));

        restore_governors(&cfg);
        assert_eq!(read_text(&cpu.join("scaling_governor")).as_deref(), Some("schedutil"));
        assert_eq!(read_text(&gpu.join("governor")).as_deref(), Some("performance"));
        assert_eq!(read_text(&mem.join("governor")).as_deref(), Some("performance"));

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn park_and_restore_cores_leaves_cpu0_online() {
        let root = test_root("cores");
        let cfg = config(&root);
        write(&cfg.sys("devices/system/cpu/cpu0/online"), "1\n");
        write(&cfg.sys("devices/system/cpu/cpu1/online"), "1\n");
        write(&cfg.sys("devices/system/cpu/cpu2/online"), "0\n");
        fs::create_dir_all(&cfg.state_dir).unwrap();

        park_cores(&cfg);
        assert_eq!(
            read_text(&cfg.sys("devices/system/cpu/cpu0/online")).as_deref(),
            Some("1")
        );
        assert_eq!(
            read_text(&cfg.sys("devices/system/cpu/cpu1/online")).as_deref(),
            Some("0")
        );
        assert_eq!(
            read_text(&cfg.sys("devices/system/cpu/cpu2/online")).as_deref(),
            Some("0")
        );

        restore_cores(&cfg);
        assert_eq!(
            read_text(&cfg.sys("devices/system/cpu/cpu1/online")).as_deref(),
            Some("1")
        );
        assert_eq!(
            read_text(&cfg.sys("devices/system/cpu/cpu2/online")).as_deref(),
            Some("0")
        );

        let _ = fs::remove_dir_all(root);
    }
}

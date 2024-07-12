use std::{
    fs::{File, OpenOptions},
    os::{fd::{AsFd, OwnedFd}, unix::fs::OpenOptionsExt},
    path::Path,
    process::Command,
};

use input::{
    event::{switch::Switch, SwitchEvent},
    Event, Libinput, LibinputInterface,
};
use libc::{O_RDONLY, O_RDWR, O_WRONLY};
use nix::poll::{poll, PollFd, PollFlags, PollTimeout};
use serde::Deserialize;

struct Interface;

impl LibinputInterface for Interface {
    #[allow(clippy::bad_bit_mask)]
    fn open_restricted(&mut self, path: &Path, flags: i32) -> Result<OwnedFd, i32> {
        OpenOptions::new()
            .custom_flags(flags)
            .read((flags & O_RDONLY != 0) | (flags & O_RDWR != 0))
            .write((flags & O_WRONLY != 0) | (flags & O_RDWR != 0))
            .open(path)
            .map(|file| file.into())
            .map_err(|err| err.raw_os_error().unwrap())
    }
    fn close_restricted(&mut self, fd: OwnedFd) {
        drop(File::from(fd));
    }
}

#[derive(Deserialize)]
struct Config {
    lid: Option<SwitchConfig>,
    tablet_mode: Option<SwitchConfig>,
}

#[derive(Deserialize)]
struct SwitchConfig {
    on: Option<String>,
    off: Option<String>,
}

fn main() {
    let config_path = dirs::config_dir().unwrap().join("switchblade.toml");
    let config: Config = toml::from_str(&std::fs::read_to_string(config_path).unwrap()).unwrap();
    let mut input = Libinput::new_with_udev(Interface);
    input.udev_assign_seat("seat0").unwrap();
    loop {
        input.dispatch().unwrap();
        for event in &mut input {
            if let Event::Switch(SwitchEvent::Toggle(event)) = event {
                if let Some(switch) = event.switch() {
                    if let Some(config) = match switch {
                        Switch::Lid => &config.lid,
                        Switch::TabletMode => &config.tablet_mode,
                        _ => &None,
                    } {
                        if let Some(cmd) = match event.switch_state() {
                            input::event::switch::SwitchState::Off => &config.off,
                            input::event::switch::SwitchState::On => &config.on,
                        } {
                            _ = Command::new("/bin/sh").arg("-c").arg(cmd).spawn();
                        }
                    }
                }
            }
        }
        let fd = PollFd::new(input.as_fd(), PollFlags::POLLIN);
        poll(&mut [fd], PollTimeout::NONE).unwrap();
    }
}

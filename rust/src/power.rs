use crate::services::command;
use std::{collections::HashMap, time::Duration};
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Profile {
    pub mode: u8,
    pub unified: bool,
}
pub fn parse(text: &str) -> HashMap<String, Profile> {
    let mut source = "";
    let mut r = HashMap::new();
    for l in text.lines().map(str::trim) {
        if l.ends_with(':') {
            source = l.trim_end_matches(':');
            continue;
        }
        if !["Battery Power", "AC Power"].contains(&source) {
            continue;
        }
        let p: Vec<_> = l.split_whitespace().collect();
        if p.len() != 2 {
            continue;
        }
        let Ok(n) = p[1].parse::<u8>() else { continue };
        if n > 2 {
            continue;
        }
        if p[0] == "powermode" {
            r.insert(
                source.into(),
                Profile {
                    mode: n,
                    unified: true,
                },
            );
        } else if p[0] == "lowpowermode" && n < 2 && !r.get(source).is_some_and(|x| x.unified) {
            r.insert(
                source.into(),
                Profile {
                    mode: n,
                    unified: false,
                },
            );
        }
    }
    r
}
pub fn read() -> HashMap<String, Profile> {
    parse(&command("/usr/bin/pmset", &["-g", "custom"], Duration::from_secs(5)).unwrap_or_default())
}
pub fn source() -> String {
    let s = command("/usr/bin/pmset", &["-g", "batt"], Duration::from_secs(5)).unwrap_or_default();
    if s.contains("'Battery Power'") {
        "Battery Power".into()
    } else {
        "AC Power".into()
    }
}
pub fn shell(source: &str, p: Profile, target: u8) -> Result<String, String> {
    let arg = match source {
        "Battery Power" => "-b",
        "AC Power" => "-c",
        _ => return Err("Unknown power source".into()),
    };
    if target > 2 || (!p.unified && target == 2) {
        return Err("Unsupported power mode".into());
    }
    Ok(format!(
        "/usr/bin/pmset {arg} {} {target}",
        if p.unified {
            "powermode"
        } else {
            "lowpowermode"
        }
    ))
}
pub fn set(source: &str, p: Profile, target: u8) -> Result<(), String> {
    let fixed = shell(source, p, target)?;
    let script=format!("do shell script \"{fixed}\" with administrator privileges with prompt \"Task Manager wants to change macOS Low Power Mode.\"");
    command(
        "/usr/bin/osascript",
        &["-e", &script],
        Duration::from_secs(120),
    )?;
    if read().get(source).map(|v| v.mode) != Some(target) {
        return Err("macOS did not apply the requested power mode.".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prefer_unified() {
        let r = parse("AC Power:\n powermode 2\n lowpowermode 0\nBattery Power:\n lowpowermode 1");
        assert_eq!(
            r["AC Power"],
            Profile {
                mode: 2,
                unified: true
            }
        );
        assert_eq!(r["Battery Power"].mode, 1)
    }
    #[test]
    fn allowlist() {
        assert!(shell(
            "AC Power; whoami",
            Profile {
                mode: 0,
                unified: true
            },
            1
        )
        .is_err());
        assert!(shell(
            "AC Power",
            Profile {
                mode: 0,
                unified: false
            },
            2
        )
        .is_err());
        assert_eq!(
            shell(
                "AC Power",
                Profile {
                    mode: 2,
                    unified: true
                },
                1
            )
            .unwrap(),
            "/usr/bin/pmset -c powermode 1"
        )
    }
}

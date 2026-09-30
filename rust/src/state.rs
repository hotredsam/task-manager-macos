use crate::{model::*, services::Service};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{Arc, Mutex},
    time::Instant,
};
pub const PAGES: [&str; 8] = [
    "Processes",
    "Performance",
    "App history",
    "Startup apps",
    "Users",
    "Details",
    "Services",
    "Settings",
];
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Preferences {
    pub start: usize,
    pub speed: u64,
    pub dark: bool,
    pub system_theme: bool,
    pub top: bool,
    pub minimize: bool,
    pub hide: bool,
    pub grouped: bool,
    pub binary: bool,
    pub logical: bool,
    pub kernel: bool,
    pub graph_seconds: usize,
    pub restore: HashMap<String, u8>,
    pub hidden: HashMap<usize, HashSet<String>>,
    pub history_all: bool,
    pub widths: HashMap<String, f64>,
}
impl Default for Preferences {
    fn default() -> Self {
        Self {
            start: 0,
            speed: 2,
            dark: false,
            system_theme: false,
            top: false,
            minimize: false,
            hide: false,
            grouped: true,
            binary: false,
            logical: false,
            kernel: false,
            graph_seconds: 60,
            restore: HashMap::new(),
            hidden: HashMap::new(),
            history_all: false,
            widths: HashMap::new(),
        }
    }
}
pub fn support() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("Library/Application Support/TaskManager")
}
impl Preferences {
    pub fn load() -> Self {
        std::fs::read(support().join("rust-preferences.json"))
            .ok()
            .and_then(|d| serde_json::from_slice(&d).ok())
            .unwrap_or_default()
    }
    pub fn save(&self) {
        let _ = std::fs::create_dir_all(support());
        if let Ok(s) = serde_json::to_vec_pretty(self) {
            let p = support().join("rust-preferences.json");
            let tmp = p.with_extension("tmp");
            if std::fs::write(&tmp, s).is_ok() {
                let _ = std::fs::rename(tmp, p);
            }
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    None,
    Page(usize),
    Resource(usize),
    Collapse,
    Minimize,
    Maximize,
    Close,
    Sort(String),
    Select(String),
    Expand(String),
    Run,
    End,
    Efficiency,
    View,
    Menu(String),
    Option(String),
    Copy,
    Properties,
    Reveal,
    SearchOnline,
    GoDetails,
    Switch,
    Signal(i32),
    Priority(i32),
    Service(String),
    Refresh,
    ResetHistory,
    GraphOnly,
    Summary,
    Kernel,
    Logical(bool),
    Snap(u8),
    Setting(String),
    Quit,
    About,
    ScrollV,
    ScrollH,
    ResizeColumn(usize),
    DialogOk,
    DialogCancel,
}
#[derive(Clone)]
pub struct Hit {
    pub rect: [f64; 4],
    pub action: Action,
    pub label: String,
    pub enabled: bool,
}
impl Hit {
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.rect[0]
            && x < self.rect[0] + self.rect[2]
            && y >= self.rect[1]
            && y < self.rect[1] + self.rect[3]
    }
}
#[derive(Clone)]
pub struct MenuItem {
    pub title: String,
    pub action: Action,
    pub enabled: bool,
    pub checked: bool,
    pub children: Vec<MenuItem>,
}
impl MenuItem {
    pub fn new(s: &str, a: Action) -> Self {
        Self {
            title: s.into(),
            action: a,
            enabled: true,
            checked: false,
            children: vec![],
        }
    }
    pub fn disabled(s: &str) -> Self {
        Self {
            enabled: false,
            ..Self::new(s, Action::None)
        }
    }
    pub fn sep() -> Self {
        Self::new("", Action::None)
    }
    pub fn sub(s: &str, children: Vec<MenuItem>) -> Self {
        Self {
            children,
            ..Self::new(s, Action::None)
        }
    }
    pub fn check(s: &str, a: Action, b: bool) -> Self {
        Self {
            checked: b,
            ..Self::new(s, a)
        }
    }
}
pub struct Menu {
    pub x: f64,
    pub y: f64,
    pub items: Vec<MenuItem>,
    pub selected: Option<usize>,
}
#[derive(Clone)]
pub struct Column {
    pub key: String,
    pub title: String,
    pub width: f64,
    pub numeric: bool,
}
fn col(k: &str, t: &str, w: f64, n: bool) -> Column {
    Column {
        key: k.into(),
        title: t.into(),
        width: w,
        numeric: n,
    }
}
pub fn columns(page: usize) -> Vec<Column> {
    match page {
        0 => vec![
            col("name", "Name", 290., false),
            col("status", "Status", 130., false),
            col("cpu", "CPU", 85., true),
            col("memory", "Memory", 100., true),
            col("disk", "Disk", 90., true),
            col("network", "Network", 90., true),
            col("gpu", "GPU", 80., true),
            col("pid", "PID", 70., true),
        ],
        2 => vec![
            col("name", "Name", 280., false),
            col("time", "CPU time", 110., true),
            col("network", "Network", 110., true),
            col("metered", "Metered network", 140., true),
            col("tile", "Notifications", 120., true),
        ],
        3 => vec![
            col("name", "Name", 290., false),
            col("publisher", "Publisher", 180., false),
            col("status", "Status", 110., false),
            col("impact", "Startup impact", 140., false),
        ],
        4 => vec![
            col("name", "User", 260., false),
            col("status", "Status", 130., false),
            col("cpu", "CPU", 90., true),
            col("memory", "Memory", 110., true),
            col("disk", "Disk", 90., true),
            col("network", "Network", 90., true),
        ],
        5 => vec![
            col("name", "Name", 260., false),
            col("pid", "PID", 75., true),
            col("status", "Status", 115., false),
            col("user", "User name", 155., false),
            col("cpu", "CPU", 85., true),
            col("memory", "Memory", 110., true),
            col("arch", "Architecture", 100., false),
            col("description", "Description", 250., false),
            col("threads", "Threads", 85., true),
            col("time", "CPU time", 100., true),
            col("path", "Image path name", 320., false),
            col("nice", "Base priority", 100., true),
            col("ppid", "Parent PID", 90., true),
            col("bundle", "Bundle identifier", 220., false),
            col("start", "Start time (Unix)", 150., true),
        ],
        6 => vec![
            col("name", "Name", 340., false),
            col("pid", "PID", 75., true),
            col("description", "Description", 300., false),
            col("status", "Status", 110., false),
            col("group", "Group", 100., false),
        ],
        _ => vec![],
    }
}
#[derive(Clone, Default)]
pub struct Row {
    pub id: String,
    pub name: String,
    pub values: HashMap<String, String>,
    pub numbers: HashMap<String, f64>,
    pub members: Vec<usize>,
    pub service: Option<usize>,
    pub icon: String,
    pub group: bool,
    pub section: bool,
    pub indent: bool,
}
impl Row {
    fn section(s: &str) -> Self {
        Self {
            id: format!("section:{s}"),
            name: s.into(),
            section: true,
            ..Default::default()
        }
    }
}
pub struct Dialog {
    pub title: String,
    pub message: String,
    pub ok: String,
    pub action: Action,
    pub input: bool,
}
pub enum Delivery {
    Operation(Result<String, String>),
    Power(Result<(String, u8, u8), String>),
    Inspector(u64, String),
}
pub struct Shared {
    pub latest: Option<Sample>,
    pub services: Option<Vec<Service>>,
    pub results: VecDeque<Delivery>,
    pub speed: u64,
    pub refresh: bool,
    pub scan: bool,
    pub stop: bool,
}
pub struct State {
    pub prefs: Preferences,
    pub page: usize,
    pub resource: usize,
    pub collapsed: bool,
    pub records: Vec<Process>,
    pub system: Snapshot,
    pub services: Vec<Service>,
    pub history: HistoryStore,
    pub samples: VecDeque<Snapshot>,
    pub rows: Vec<Row>,
    pub columns: Vec<Column>,
    pub expanded: HashSet<String>,
    pub regular_apps: HashSet<String>,
    pub selected: Option<String>,
    pub selections: HashSet<String>,
    pub query: String,
    pub sort: String,
    pub ascending: bool,
    pub scroll: f64,
    pub hscroll: f64,
    pub hits: Vec<Hit>,
    pub hover: Action,
    pub focus: Action,
    pub menus: Vec<Menu>,
    pub dialog: Option<Dialog>,
    pub dialog_scroll: f64,
    pub inspector_generation: u64,
    pub graph_only: bool,
    pub summary: bool,
    pub memory_percent: bool,
    pub power_on: bool,
    pub login_enabled: bool,
    pub busy: bool,
    pub shared: Arc<Mutex<Shared>>,
    pub width: f64,
    pub height: f64,
    pub settings_height: f64,
    pub drag: Option<(Action, f64, f64, f64)>,
    pub last_save: Instant,
    pub redraw_ms: VecDeque<f64>,
}
impl State {
    pub fn new() -> Self {
        let prefs = Preferences::load();
        let mut history = HistoryStore::default();
        history.entries = std::fs::read(support().join("rust-history.json"))
            .ok()
            .and_then(|s| serde_json::from_slice(&s).ok())
            .unwrap_or_default();
        let shared = Arc::new(Mutex::new(Shared {
            latest: None,
            services: None,
            results: VecDeque::new(),
            speed: prefs.speed,
            refresh: true,
            scan: true,
            stop: false,
        }));
        let mut s = Self {
            page: prefs.start.min(7),
            prefs,
            resource: 0,
            collapsed: false,
            records: vec![],
            system: Snapshot::default(),
            services: vec![],
            history,
            samples: VecDeque::new(),
            rows: vec![],
            columns: vec![],
            expanded: HashSet::new(),
            regular_apps: HashSet::new(),
            selected: None,
            selections: HashSet::new(),
            query: String::new(),
            sort: "cpu".into(),
            ascending: false,
            scroll: 0.,
            hscroll: 0.,
            hits: vec![],
            hover: Action::None,
            focus: Action::None,
            menus: vec![],
            dialog: None,
            dialog_scroll: 0.,
            inspector_generation: 0,
            graph_only: false,
            summary: false,
            memory_percent: false,
            power_on: false,
            login_enabled: false,
            busy: false,
            shared,
            width: 1120.,
            height: 720.,
            settings_height: 960.,
            drag: None,
            last_save: Instant::now(),
            redraw_ms: VecDeque::new(),
        };
        s.reset_columns();
        s
    }
    pub fn save(&self) {
        self.prefs.save();
        if let Ok(s) = serde_json::to_vec(&self.history.entries) {
            let _ = std::fs::write(support().join("rust-history.json"), s);
        }
    }
    pub fn sidebar(&self) -> f64 {
        if self.graph_only {
            0.
        } else if self.collapsed {
            48.
        } else {
            240.
        }
    }
    pub fn reset_columns(&mut self) {
        let hidden = self.prefs.hidden.get(&self.page);
        self.columns = columns(self.page)
            .into_iter()
            .filter(|c| {
                if let Some(hidden) = hidden {
                    !hidden.contains(&c.key)
                } else {
                    match self.page {
                        0 => !["gpu", "pid"].contains(&c.key.as_str()),
                        5 => !["threads", "time", "path", "nice", "ppid", "bundle", "start"]
                            .contains(&c.key.as_str()),
                        _ => true,
                    }
                }
            })
            .map(|mut c| {
                if let Some(w) = self.prefs.widths.get(&format!("{}:{}", self.page, c.key)) {
                    c.width = (*w).clamp(55., 900.);
                }
                c
            })
            .collect()
    }
    pub fn set_page(&mut self, n: usize) {
        self.page = n.min(7);
        self.sort = if [0, 5].contains(&n) { "cpu" } else { "name" }.into();
        self.ascending = ![0, 5].contains(&n);
        self.selected = None;
        self.selections.clear();
        self.scroll = 0.;
        self.hscroll = 0.;
        self.menus.clear();
        self.reset_columns();
        self.rebuild();
    }
    pub fn current(&self) -> Option<&Row> {
        self.selected
            .as_ref()
            .and_then(|id| self.rows.iter().find(|r| &r.id == id))
    }
    pub fn process(&self) -> Option<&Process> {
        self.current()?
            .members
            .first()
            .and_then(|&i| self.records.get(i))
    }
    pub fn selected_processes(&self) -> Vec<&Process> {
        let mut seen = HashSet::new();
        self.rows
            .iter()
            .filter(|r| self.selections.contains(&r.id) || self.selected.as_ref() == Some(&r.id))
            .flat_map(|r| r.members.iter().map(|&i| &self.records[i]))
            .filter(|p| seen.insert(p.id()))
            .collect()
    }
    pub fn can_end(&self) -> bool {
        let selected = self.selected_processes();
        !selected.is_empty() && self.page != 4 && selected.iter().all(|p| !p.protected())
    }
    pub fn row_height(&self) -> f64 {
        if [5, 6, 3, 2].contains(&self.page) {
            24.
        } else {
            28.
        }
    }
    pub fn header_height(&self) -> f64 {
        if [0, 4].contains(&self.page) {
            56.
        } else {
            30.
        }
    }
    pub fn table_top(&self) -> f64 {
        96. + self.header_height() + if self.page == 2 { 46. } else { 0. }
    }
    pub fn max_scroll(&self) -> f64 {
        if self.page == 7 {
            return (self.settings_height - self.height).max(0.);
        }
        (self.rows.len() as f64 * self.row_height() - (self.height - self.table_top() - 15.))
            .max(0.)
    }
    pub fn clamp_scroll(&mut self) {
        self.scroll = self.scroll.clamp(0., self.max_scroll());
        let total: f64 = self.columns.iter().map(|c| c.width).sum();
        self.hscroll = self
            .hscroll
            .clamp(0., (total - (self.width - self.sidebar() - 15.)).max(0.));
    }
    fn process_row(&self, members: Vec<usize>, id: String, name: String, group: bool) -> Row {
        let first = &self.records[members[0]];
        let mut r = Row {
            id,
            name,
            group,
            icon: if first.app.is_empty() {
                first.path.clone()
            } else {
                first.app.clone()
            },
            values: HashMap::with_capacity(self.columns.len()),
            numbers: HashMap::with_capacity(9),
            ..Default::default()
        };
        let (mut valid, mut io, mut cpu, mut mem, mut disk, mut threads, mut time) =
            (false, false, 0., 0., 0., 0., 0.);
        for &i in &members {
            let p = &self.records[i];
            valid |= p.raw.valid != 0;
            io |= p.raw.io_valid != 0;
            cpu += p.cpu;
            mem += p.raw.memory as f64;
            disk += p.read + p.write;
            threads += p.raw.threads as f64;
            time += p.raw.cpu_ns as f64 / 1e9;
        }
        for (key, value) in [
            ("pid", first.raw.pid as f64),
            ("nice", first.raw.nice as f64),
            ("ppid", first.raw.ppid as f64),
            ("start", first.raw.start as f64),
        ] {
            r.numbers.insert(key.into(), value);
        }
        if valid {
            for (key, value) in [
                ("cpu", cpu),
                ("memory", mem),
                ("threads", threads),
                ("time", time),
            ] {
                r.numbers.insert(key.into(), value);
            }
        }
        if io {
            r.numbers.insert("disk".into(), disk);
        }
        // Keep sortable text only; numerical strings are formatted for visible cells on demand.
        for column in &self.columns {
            let value = match column.key.as_str() {
                "status" => {
                    if self.page == 5 {
                        first.status().into()
                    } else if first.raw.state == 4 {
                        "Suspended".into()
                    } else {
                        String::new()
                    }
                }
                "user" => first.user.clone(),
                "description" => first.title.clone(),
                "path" => first.path.clone(),
                "bundle" => first.bundle.clone(),
                "arch" => match first.raw.arch {
                    0x0100000c => "ARM64",
                    0x01000007 => "x64",
                    _ => "—",
                }
                .into(),
                _ => continue,
            };
            r.values.insert(column.key.clone(), value);
        }
        r.members = members;
        r
    }
    pub fn row_value<'a>(&self, row: &'a Row, key: &str) -> std::borrow::Cow<'a, str> {
        if let Some(value) = row.values.get(key) {
            return std::borrow::Cow::Borrowed(value);
        }
        let Some(&number) = row.numbers.get(key) else {
            return std::borrow::Cow::Borrowed("—");
        };
        std::borrow::Cow::Owned(match key {
            "cpu" => format!("{number:0.1}%"),
            "memory" => {
                if self.memory_percent {
                    format!("{:0.1}%", number / self.system.raw.ram.max(1) as f64 * 100.)
                } else {
                    bytes(number, self.prefs.binary)
                }
            }
            "disk" => format!("{}/s", bytes(number, self.prefs.binary)),
            "time" => duration(number),
            _ => format!("{number:0.0}"),
        })
    }
    pub fn rebuild(&mut self) {
        let q = self.query.trim().to_lowercase();
        let mut rows = vec![];
        match self.page {
            0 | 5 => {
                if self.page == 0 && self.prefs.grouped {
                    for (key, name, members) in group_processes(&self.records) {
                        if !members.iter().any(|&i| self.records[i].matches(&q)) {
                            continue;
                        }
                        rows.push(self.process_row(members, key, name, true));
                    }
                } else {
                    for (i, p) in self
                        .records
                        .iter()
                        .enumerate()
                        .filter(|(_, p)| p.matches(&q))
                    {
                        rows.push(self.process_row(
                            vec![i],
                            p.id(),
                            if self.page == 5 {
                                p.name.clone()
                            } else {
                                p.title.clone()
                            },
                            false,
                        ));
                    }
                }
            }
            2 => {
                for (k, h) in &self.history.entries {
                    if (!self.prefs.history_all
                        && !(h.path.starts_with("/Applications/")
                            || h.path.starts_with("/System/Applications/")))
                        || !h.name.to_lowercase().contains(&q)
                    {
                        continue;
                    }
                    let mut r = Row {
                        id: k.clone(),
                        name: h.name.clone(),
                        icon: h.path.clone(),
                        ..Default::default()
                    };
                    r.numbers.insert("time".into(), h.cpu);
                    r.values.insert("time".into(), duration(h.cpu));
                    rows.push(r);
                }
            }
            3 | 6 => {
                for (i, s) in self.services.iter().enumerate() {
                    if self.page == 3
                        && (!s.domain.starts_with("gui/")
                            || s.path.is_empty()
                            || s.path.starts_with("/System/")
                            || s.label.starts_with("com.apple."))
                    {
                        continue;
                    }
                    if ![
                        &s.label,
                        &s.program,
                        &s.publisher,
                        &s.pid.unwrap_or_default().to_string(),
                    ]
                    .iter()
                    .any(|v| v.to_lowercase().contains(&q))
                    {
                        continue;
                    }
                    let mut r = Row {
                        id: s.id(),
                        name: s.label.clone(),
                        service: Some(i),
                        icon: if self.page == 6 {
                            "service.item".into()
                        } else {
                            s.program.clone()
                        },
                        ..Default::default()
                    };
                    if let Some(p) = s.pid {
                        r.numbers.insert("pid".into(), p as f64);
                        r.values.insert("pid".into(), p.to_string());
                    }
                    r.values.insert(
                        "status".into(),
                        if self.page == 3 {
                            if s.disabled {
                                "Disabled"
                            } else {
                                "Enabled"
                            }
                        } else {
                            s.status()
                        }
                        .into(),
                    );
                    r.values.insert("publisher".into(), s.publisher.clone());
                    r.values.insert("description".into(), s.program.clone());
                    r.values.insert("group".into(), s.domain.clone());
                    r.values.insert("impact".into(), "Not measured".into());
                    rows.push(r);
                }
            }
            4 => {
                let mut groups: HashMap<i32, Vec<usize>> = HashMap::new();
                for (i, p) in self.records.iter().enumerate() {
                    if p.raw.uid >= 500 {
                        groups.entry(p.raw.uid).or_default().push(i)
                    }
                }
                for (uid, m) in groups {
                    let name = self.records[m[0]].user.clone();
                    if !name.to_lowercase().contains(&q) {
                        continue;
                    }
                    let mut r = self.process_row(m, format!("user:{uid}"), name, true);
                    r.values.insert(
                        "status".into(),
                        if uid == unsafe { libc::getuid() } as i32 {
                            "Active"
                        } else {
                            ""
                        }
                        .into(),
                    );
                    rows.push(r);
                }
            }
            _ => {}
        }
        let key = &self.sort;
        let asc = self.ascending;
        rows.sort_by(|a, b| {
            let av = a.numbers.get(key);
            let bv = b.numbers.get(key);
            let c = match (av, bv) {
                (Some(a), Some(b)) => a.total_cmp(b),
                (None, Some(_)) => return std::cmp::Ordering::Greater,
                (Some(_), None) => return std::cmp::Ordering::Less,
                _ => {
                    let at = if key == "name" {
                        &a.name
                    } else {
                        a.values.get(key).map(String::as_str).unwrap_or("")
                    };
                    let bt = if key == "name" {
                        &b.name
                    } else {
                        b.values.get(key).map(String::as_str).unwrap_or("")
                    };
                    at.to_lowercase().cmp(&bt.to_lowercase())
                }
            };
            let c = if asc { c } else { c.reverse() };
            c.then_with(|| a.id.cmp(&b.id))
        });
        if self.page == 0 && self.prefs.grouped {
            let (mut apps, mut background, mut system) = (vec![], vec![], vec![]);
            for r in rows {
                if self.regular_apps.contains(&r.id) {
                    apps.push(r)
                } else if self.records[r.members[0]].raw.uid == unsafe { libc::getuid() } as i32 {
                    background.push(r)
                } else {
                    system.push(r)
                }
            }
            rows = vec![];
            for (name, group) in [
                ("Apps", apps),
                ("Background processes", background),
                ("Windows processes", system),
            ] {
                if !group.is_empty() {
                    rows.push(Row::section(&format!(
                        "{} ({})",
                        if name == "Windows processes" {
                            "System processes"
                        } else {
                            name
                        },
                        group.len()
                    )));
                    rows.extend(group);
                }
            }
        }
        let mut expanded = vec![];
        for r in rows {
            let open = r.group && self.expanded.contains(&r.id);
            let m = r.members.clone();
            expanded.push(r);
            if open {
                for i in m {
                    let p = &self.records[i];
                    let mut child = self.process_row(
                        vec![i],
                        format!("child:{}", p.id()),
                        p.name.clone(),
                        false,
                    );
                    child.indent = true;
                    expanded.push(child);
                }
            }
        }
        self.rows = expanded;
        self.selections
            .retain(|id| self.rows.iter().any(|r| &r.id == id));
        if self
            .selected
            .as_ref()
            .is_some_and(|id| !self.rows.iter().any(|r| &r.id == id))
        {
            self.selected = None;
        }
        self.clamp_scroll();
    }
    pub fn selected_visible(&mut self) {
        if let Some(i) = self
            .selected
            .as_ref()
            .and_then(|id| self.rows.iter().position(|r| &r.id == id))
        {
            let y = i as f64 * self.row_height();
            let h = self.height - self.table_top() - 15.;
            if y < self.scroll {
                self.scroll = y;
            } else if y + self.row_height() > self.scroll + h {
                self.scroll = y + self.row_height() - h;
            }
            self.clamp_scroll();
        }
    }
}
pub fn workers(shared: Arc<Mutex<Shared>>) {
    let sample_shared = shared.clone();
    std::thread::spawn(move || {
        let mut sampler = Sampler::default();
        let mut next = Instant::now();
        let mut paused = false;
        loop {
            let (speed, refresh, stop) = {
                let mut s = sample_shared.lock().unwrap();
                let v = (s.speed, s.refresh, s.stop);
                s.refresh = false;
                v
            };
            if stop {
                break;
            }
            if speed == 0 {
                paused = true;
            } else if paused {
                sampler.reset();
                paused = false;
                next = Instant::now();
            }
            if refresh || (speed > 0 && Instant::now() >= next) {
                let sample = sampler.sample();
                sample_shared.lock().unwrap().latest = Some(sample);
                next = Instant::now() + std::time::Duration::from_secs(speed.max(1));
            }
            std::thread::sleep(std::time::Duration::from_millis(40));
        }
    });
    std::thread::spawn(move || {
        let mut next = Instant::now();
        loop {
            let (scan, speed, stop) = {
                let mut s = shared.lock().unwrap();
                let v = (s.scan, s.speed, s.stop);
                s.scan = false;
                v
            };
            if stop {
                break;
            }
            if scan || (speed > 0 && Instant::now() >= next) {
                let rows = crate::services::scan();
                shared.lock().unwrap().services = Some(rows);
                next = Instant::now() + std::time::Duration::from_secs(15)
            }
            std::thread::sleep(std::time::Duration::from_millis(150));
        }
    });
}

pub fn benchmark_model() {
    let mut sampler = Sampler::default();
    let sample = sampler.sample();
    let mut state = State::new();
    state.records = sample.processes;
    state.system = sample.system;
    let mut rows = vec![];
    for page in [0, 4, 5] {
        for key in ["name", "cpu", "memory", "disk", "network"] {
            state.set_page(page);
            state.sort = key.to_string();
            let mut ms = vec![];
            for _ in 0..100 {
                let start = Instant::now();
                state.ascending = !state.ascending;
                state.rebuild();
                ms.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            ms.sort_by(f64::total_cmp);
            rows.push(serde_json::json!({"page":PAGES[page],"sort":key,"rows":state.rows.len(),"p50_ms":ms[50],"p95_ms":ms[95],"max_ms":ms[99]}));
        }
    }
    println!("{}", serde_json::to_string_pretty(&serde_json::json!({"process_count":state.records.len(),"measurement":"model rebuild only; excludes rendering and compositor", "results":rows})).unwrap());
}

impl State {
    /// Header clicks reorder the prepared rows without reformatting every metric.
    /// Preserve expansion and selection identities while keeping section headings fixed.
    pub fn sort_rows(&mut self) {
        let mut tops = Vec::new();
        let mut children: HashMap<String, Vec<Row>> = HashMap::new();
        let mut parent = String::new();
        for row in std::mem::take(&mut self.rows) {
            if row.section {
                continue;
            }
            if row.indent {
                children.entry(parent.clone()).or_default().push(row);
            } else {
                parent = row.id.clone();
                tops.push(row);
            }
        }
        let key = &self.sort;
        let asc = self.ascending;
        tops.sort_by(|a, b| {
            let c = match (a.numbers.get(key), b.numbers.get(key)) {
                (Some(a), Some(b)) => a.total_cmp(b),
                (None, Some(_)) => return std::cmp::Ordering::Greater,
                (Some(_), None) => return std::cmp::Ordering::Less,
                _ => {
                    let a = if key == "name" {
                        a.name.as_str()
                    } else {
                        a.values.get(key).map(String::as_str).unwrap_or("")
                    };
                    let b = if key == "name" {
                        b.name.as_str()
                    } else {
                        b.values.get(key).map(String::as_str).unwrap_or("")
                    };
                    a.to_lowercase().cmp(&b.to_lowercase())
                }
            };
            (if asc { c } else { c.reverse() }).then_with(|| a.id.cmp(&b.id))
        });
        if self.page == 0 && self.prefs.grouped {
            let mut groups: [Vec<Row>; 3] = Default::default();
            for row in tops {
                let group =
                    if self.regular_apps.contains(&row.id) {
                        0
                    } else if row.members.first().is_some_and(|&i| {
                        self.records[i].raw.uid == unsafe { libc::getuid() } as i32
                    }) {
                        1
                    } else {
                        2
                    };
                groups[group].push(row);
            }
            for (name, group) in ["Apps", "Background processes", "System processes"]
                .into_iter()
                .zip(groups)
            {
                if group.is_empty() {
                    continue;
                }
                self.rows
                    .push(Row::section(&format!("{name} ({})", group.len())));
                for row in group {
                    let child = children.remove(&row.id).unwrap_or_default();
                    self.rows.push(row);
                    self.rows.extend(child);
                }
            }
        } else {
            for row in tops {
                let child = children.remove(&row.id).unwrap_or_default();
                self.rows.push(row);
                self.rows.extend(child);
            }
        }
        self.clamp_scroll();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_table_column_has_sortable_identity() {
        for page in [0, 2, 3, 4, 5, 6] {
            let cols = columns(page);
            assert!(!cols.is_empty());
            let ids: HashSet<_> = cols.iter().map(|c| &c.key).collect();
            assert_eq!(ids.len(), cols.len());
            assert!(cols.iter().all(|c| c.width >= 55.));
        }
    }
    #[test]
    fn cached_sort_preserves_selection_and_unknown_last() {
        let mut s = State::new();
        s.page = 5;
        s.rows = vec![
            Row {
                id: "a".into(),
                name: "a".into(),
                numbers: HashMap::from([("cpu".into(), 2.)]),
                ..Default::default()
            },
            Row {
                id: "b".into(),
                name: "b".into(),
                numbers: HashMap::from([("cpu".into(), 8.)]),
                ..Default::default()
            },
            Row {
                id: "unknown".into(),
                name: "unknown".into(),
                ..Default::default()
            },
        ];
        s.sort = "cpu".into();
        s.ascending = false;
        s.selected = Some("a".into());
        s.sort_rows();
        assert_eq!(s.rows[0].id, "b");
        assert_eq!(s.rows[2].id, "unknown");
        assert_eq!(s.selected.as_deref(), Some("a"));
        s.ascending = true;
        s.sort_rows();
        assert_eq!(s.rows[0].id, "a");
        assert_eq!(s.rows[2].id, "unknown");
    }
    #[test]
    fn no_negative_scroll() {
        let mut s = State::new();
        s.scroll = -100.;
        s.hscroll = -50.;
        s.clamp_scroll();
        assert_eq!(s.scroll, 0.);
        assert_eq!(s.hscroll, 0.);
    }
    #[test]
    fn navigation_resets_selection() {
        let mut s = State::new();
        s.selected = Some("a".into());
        s.selections.insert("a".into());
        s.set_page(6);
        assert!(s.selected.is_none());
        assert!(s.selections.is_empty());
    }
}

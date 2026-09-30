use crate::{
    draw::{self, rect, Painter},
    model, power, services,
    state::*,
};
use objc2::AnyThread;
use objc2::{
    define_class, msg_send,
    rc::Retained,
    runtime::{AnyObject, ProtocolObject},
    sel, DefinedClass, MainThreadOnly,
};
use objc2_app_kit::*;
use objc2_foundation::*;
use std::{
    cell::{OnceCell, RefCell},
    collections::VecDeque,
    time::{Duration, Instant},
};
struct Ivars {
    state: RefCell<State>,
    painter: RefCell<Painter>,
    search: OnceCell<Retained<NSTextField>>,
    input: OnceCell<Retained<NSTextField>>,
    restore: RefCell<Option<NSRect>>,
    timings: RefCell<VecDeque<(String, f64)>>,
    ax_nodes: RefCell<Vec<Retained<AnyObject>>>,
    recording: RefCell<Option<WindowRecording>>,
}
define_class!(
 #[unsafe(super=NSView)] #[thread_kind=MainThreadOnly] #[ivars=Ivars] struct Canvas;
 unsafe impl NSObjectProtocol for Canvas{}
 impl Canvas{
  #[unsafe(method_id(accessibilityChildren))]
  fn accessibility_children(&self)->Retained<NSArray<AnyObject>>{self.ax_children()}
  #[unsafe(method_id(accessibilityChildrenInNavigationOrder))]
  fn navigation_children(&self)->Retained<NSArray<AnyObject>>{self.ax_children()}
  #[unsafe(method(isFlipped))]fn flipped(&self)->bool{true}
  #[unsafe(method(acceptsFirstResponder))]fn accepts(&self)->bool{true}
  #[unsafe(method(drawRect:))]fn draw_rect(&self,_rect:NSRect){let start=Instant::now();{let mut s=self.ivars().state.borrow_mut();let bounds=self.bounds();s.width=bounds.size.width;s.height=bounds.size.height;draw::render(&mut self.ivars().painter.borrow_mut(),&mut s);if let Some(h)=s.hits.iter().find(|h|h.action==s.focus && s.focus!=Action::None){self.ivars().painter.borrow().outline(h.rect,&draw::rgb(0.,0.4,0.64),1.,2.);}model::push_history(&mut s.redraw_ms,start.elapsed().as_secs_f64()*1000.,1024);} }
  #[unsafe(method(setFrameSize:))]fn frame_size(&self,size:NSSize){unsafe{let _:()=msg_send![super(self),setFrameSize:size];}self.layout_fields();}
  #[unsafe(method(mouseDown:))]fn mouse_down(&self,e:&NSEvent){let pt=self.convertPoint_fromView(e.locationInWindow(),None);let a=self.hit(pt.x,pt.y);if a==Action::None&&pt.y<48.{if e.clickCount()==2{self.dispatch(Action::Maximize)}else if let Some(w)=self.window(){w.performWindowDragWithEvent(e);}return}
   if [Action::ScrollV,Action::ScrollH].contains(&a)||matches!(a,Action::ResizeColumn(_)){let mut s=self.ivars().state.borrow_mut();let offset=match a{Action::ScrollH=>s.hscroll,Action::ResizeColumn(i)=>s.columns[i].width,_=>s.scroll};s.drag=Some((a.clone(),pt.x,pt.y,offset));drop(s);self.drag_scroll(&a,pt.x,pt.y,true);return}
   if let Action::Select(ref id)=a {
     let flags=e.modifierFlags();
     if flags.contains(NSEventModifierFlags::Command)||flags.contains(NSEventModifierFlags::Shift) {
       let mut s=self.ivars().state.borrow_mut();
       if flags.contains(NSEventModifierFlags::Shift){let from=s.selected.as_ref().and_then(|id|s.rows.iter().position(|r|&r.id==id));let to=s.rows.iter().position(|r|&r.id==id);if let(Some(a),Some(b))=(from,to){let ids=s.rows[a.min(b)..=a.max(b)].iter().filter(|r|!r.section).map(|r|r.id.clone()).collect::<Vec<_>>();s.selections.extend(ids);}}
       else {if let Some(old)=s.selected.clone(){s.selections.insert(old);}if !s.selections.remove(id){s.selections.insert(id.clone());}}
       s.selected=if s.selections.contains(id){Some(id.clone())}else{s.selections.iter().next().cloned()};drop(s);self.redraw();return;
     }
   }
   if let Action::Select(ref id)=a{if e.clickCount()==2{let group=self.ivars().state.borrow().rows.iter().any(|r|&r.id==id&&r.group);self.dispatch(if group{Action::Expand(id.clone())}else{Action::Properties});return}}
   if e.clickCount()==2 && matches!(a,Action::Menu(_)){self.dispatch(Action::GraphOnly);return}
   if let Some(w)=self.window(){w.makeFirstResponder(Some(self));}self.ivars().state.borrow_mut().focus=Action::None;self.dispatch(a);
  }
  #[unsafe(method(mouseUp:))]fn mouse_up(&self,_e:&NSEvent){self.ivars().state.borrow_mut().drag=None;}
  #[unsafe(method(mouseDragged:))]fn mouse_dragged(&self,e:&NSEvent){let pt=self.convertPoint_fromView(e.locationInWindow(),None);let a=self.ivars().state.borrow().drag.as_ref().map(|v|v.0.clone());if let Some(a)=a{self.drag_scroll(&a,pt.x,pt.y,false)}}
  #[unsafe(method(rightMouseDown:))]fn right_down(&self,e:&NSEvent){let pt=self.convertPoint_fromView(e.locationInWindow(),None);let a=self.hit(pt.x,pt.y);let mut s=self.ivars().state.borrow_mut();if let Action::Select(id)=a{if !s.selections.contains(&id){s.selections.clear();}s.selected=Some(id)}let items=if pt.y<48.{system_menu()}else if s.page==1{graph_menu(&s)}else{row_menu(&s)};open_menu(&mut s,items,pt.x,pt.y);drop(s);self.redraw();}
  #[unsafe(method(mouseMoved:))]fn mouse_moved(&self,e:&NSEvent){let pt=self.convertPoint_fromView(e.locationInWindow(),None);let a=self.hit(pt.x,pt.y);let mut s=self.ivars().state.borrow_mut();if a==s.hover{return}s.hover=a.clone();let mut submenu=None;if let Action::Option(ref value)=a{if let Some((depth,index))=parse_menu(value){if let Some(menu)=s.menus.get_mut(depth){menu.selected=Some(index);if let Some(item)=menu.items.get(index){if !item.children.is_empty(){let yy=menu.y+4.+menu.items[..index].iter().map(|v|if v.title.is_empty(){9.}else{30.}).sum::<f64>();submenu=Some((depth,menu.x+252.,yy,item.children.clone()));}else{s.menus.truncate(depth+1);}}}}}if let Some((d,x,y,items))=submenu{s.menus.truncate(d+1);let x=if x+252.>s.width{(x-504.).max(0.)}else{x};let y=y.min((s.height-menu_height(&items)).max(0.));s.menus.push(Menu{x,y,items,selected:None});}drop(s);self.setNeedsDisplay(true);}
  #[unsafe(method(mouseExited:))]fn mouse_exited(&self,_e:&NSEvent){self.ivars().state.borrow_mut().hover=Action::None;self.setNeedsDisplay(true);}
  #[unsafe(method(scrollWheel:))]fn scroll_wheel(&self,e:&NSEvent){let mut s=self.ivars().state.borrow_mut();if let Some(d)=&s.dialog{if d.title.ends_with(" Properties"){s.dialog_scroll=(s.dialog_scroll-e.scrollingDeltaY()*8.).max(0.);drop(s);self.redraw();}return}if !s.menus.is_empty(){return}let factor=if e.hasPreciseScrollingDeltas(){1.}else{20.};if s.page==7{s.scroll=(s.scroll-e.scrollingDeltaY()*factor).clamp(0.,s.max_scroll());}else if ![1,7].contains(&s.page){s.scroll-=e.scrollingDeltaY()*factor;s.hscroll-=e.scrollingDeltaX()*factor;s.clamp_scroll();}drop(s);self.redraw();}
  #[unsafe(method(keyDown:))]fn key_down(&self,e:&NSEvent){if !self.key(e){unsafe{let _:()=msg_send![super(self),keyDown:e];}}}
  #[unsafe(method(performKeyEquivalent:))]fn equivalent(&self,e:&NSEvent)->bool{self.key(e)}
  #[unsafe(method(tick:))]fn tick(&self,_timer:&NSTimer){self.poll();self.record_frame();}
  #[unsafe(method(menuAction:))]fn menu_action(&self,item:&NSMenuItem){let n=item.tag();self.dispatch(match n{0..=7=>Action::Page(n as usize),10=>Action::Run,11=>Action::Refresh,12=>Action::Setting("speed".into()),13=>Action::About,14=>Action::Quit,15=>{self.focus_search();return},_=>Action::None});}
 }
 unsafe impl NSTextFieldDelegate for Canvas{}
 unsafe impl NSControlTextEditingDelegate for Canvas{
  #[unsafe(method(controlTextDidChange:))]fn text_changed(&self,_notification:&NSNotification){if let Some(field)=self.ivars().search.get(){let mut s=self.ivars().state.borrow_mut();s.query=field.stringValue().to_string();s.scroll=0.;s.rebuild();drop(s);self.redraw();}}
 }
);
impl Canvas {
    pub fn new(mtm: MainThreadMarker) -> Retained<Self> {
        let mut s = State::new();
        s.login_enabled = login_enabled();
        workers(s.shared.clone());
        let this = Self::alloc(mtm).set_ivars(Ivars {
            state: RefCell::new(s),
            painter: RefCell::new(Painter::new(mtm)),
            search: OnceCell::new(),
            input: OnceCell::new(),
            restore: RefCell::new(None),
            timings: RefCell::new(VecDeque::new()),
            ax_nodes: RefCell::new(Vec::new()),
            recording: RefCell::new(None),
        });
        let this: Retained<Self> =
            unsafe { msg_send![super(this),initWithFrame:rect(0.,0.,1120.,720.)] };
        let field = unsafe {
            NSTextField::initWithFrame(NSTextField::alloc(mtm), rect(350., 12., 420., 28.))
        };
        unsafe {
            field.setFont(Some(&this.ivars().painter.borrow_mut().font(12., false)));
            field.setBezeled(false);
            field.setDrawsBackground(false);
            field.setFocusRingType(NSFocusRingType::None);
            field.setPlaceholderString(None);
            field.setDelegate(Some(ProtocolObject::from_ref(&*this)));
            field.setUsesSingleLineMode(true);
            field.setLineBreakMode(NSLineBreakMode::ByClipping);
            this.addSubview(&field);
        }
        this.ivars().search.set(field).unwrap();
        let input =
            unsafe { NSTextField::initWithFrame(NSTextField::alloc(mtm), rect(0., 0., 200., 26.)) };
        unsafe {
            input.setFont(Some(&this.ivars().painter.borrow_mut().font(12., false)));
            input.setHidden(true);
            this.addSubview(&input);
        }
        this.ivars().input.set(input).unwrap();
        let tracking = unsafe {
            NSTrackingArea::initWithRect_options_owner_userInfo(
                NSTrackingArea::alloc(),
                rect(0., 0., 0., 0.),
                NSTrackingAreaOptions::MouseMoved
                    | NSTrackingAreaOptions::MouseEnteredAndExited
                    | NSTrackingAreaOptions::ActiveInKeyWindow
                    | NSTrackingAreaOptions::InVisibleRect,
                Some(&this),
                None,
            )
        };
        this.addTrackingArea(&tracking);
        unsafe {
            let timer = NSTimer::scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
                0.05,
                &this,
                sel!(tick:),
                None,
                true,
            );
            NSRunLoop::mainRunLoop().addTimer_forMode(&timer, NSRunLoopCommonModes);
        }
        unsafe {
            let _: () = msg_send![&*this,setAccessibilityElement:true];
            let _: () = msg_send![&*this,setAccessibilityRole:ns_string!("AXGroup")];
        }
        this.ivars().painter.borrow_mut().load_image("appicon");
        this.layout_fields();
        this
    }
    fn hit(&self, x: f64, y: f64) -> Action {
        let s = self.ivars().state.borrow();
        if let Some(h) = s.hits.iter().rev().find(|h| h.contains(x, y)) {
            if s.dialog.is_some()
                && !(matches!(h.action, Action::DialogOk | Action::DialogCancel)
                    || h.action == Action::Option("copy-properties".into()))
            {
                return Action::None;
            }
            if !s.menus.is_empty()
                && !matches!(h.action,Action::Option(ref v)if v.starts_with("menu:"))
            {
                return Action::None;
            }
            if h.enabled {
                return h.action.clone();
            }
        }
        Action::None
    }
    fn redraw(&self) {
        self.layout_fields();
        self.setNeedsDisplay(true);
    }
    fn layout_fields(&self) {
        let b = self.bounds();
        if let Ok(mut s) = self.ivars().state.try_borrow_mut() {
            s.width = b.size.width;
            s.height = b.size.height;
            let hidden = s.graph_only || ![0, 3, 4, 5, 6].contains(&s.page) || s.dialog.is_some();
            if let Some(f) = self.ivars().search.get() {
                let width = (s.width - 630.).clamp(240., 500.);
                let x = (s.width - width) / 2.;
                f.setFrame(rect(x + 12., 17., width - 52., 22.));
                f.setHidden(hidden);
                unsafe {
                    f.setTextColor(Some(&draw::gray(if s.prefs.dark { 0.94 } else { 0.1 })));
                }
            }
            if let Some(f) = self.ivars().input.get() {
                let show = s.dialog.as_ref().is_some_and(|d| d.input);
                f.setHidden(!show);
                if show {
                    f.setFrame(rect(
                        (s.width - 480.) / 2. + 24.,
                        (s.height - 224.) / 2. + 118.,
                        432.,
                        28.,
                    ));
                }
            }
        }
    }
    fn focus_search(&self) {
        if let Some(f) = self.ivars().search.get() {
            if let Some(w) = self.window() {
                w.makeFirstResponder(Some(f));
            }
        }
    }
    fn poll(&self) {
        // Rows hold indices into the snapshot. Keep both frozen while a menu,
        // confirmation, or drag refers to them; the worker retains the newest sample.
        let frozen = {
            let s = self.ivars().state.borrow();
            s.dialog.is_some() || !s.menus.is_empty() || s.drag.is_some()
        };
        let shared = self.ivars().state.borrow().shared.clone();
        let (sample, services, results) = {
            let mut q = shared.lock().unwrap();
            (
                if frozen { None } else { q.latest.take() },
                if frozen { None } else { q.services.take() },
                q.results.drain(..).collect::<Vec<_>>(),
            )
        };
        let icons_changed = self.ivars().painter.borrow_mut().warm_images();
        let mut changed = false;
        {
            let mut s = self.ivars().state.borrow_mut();
            if let Some(sample) = sample {
                if s.prefs.speed != 0 {
                    s.history.ingest(&sample.processes, sample.system.elapsed);
                }
                s.regular_apps = NSWorkspace::sharedWorkspace()
                    .runningApplications()
                    .iter()
                    .filter(|app| app.activationPolicy() == NSApplicationActivationPolicy::Regular)
                    .filter_map(|app| {
                        app.bundleURL()
                            .and_then(|url| url.path())
                            .map(|p| p.to_string())
                    })
                    .collect();
                s.records = sample.processes;
                s.system = sample.system;
                let system = s.system.clone();
                model::push_history(&mut s.samples, system, 301);
                changed = true;
            }
            if let Some(services) = services {
                s.services = services;
                changed = true;
            }
            for r in results {
                s.busy = false;
                match r {
                    Delivery::Operation(Err(e)) => {
                        s.dialog = Some(Dialog {
                            title: "Task Manager".into(),
                            message: e,
                            ok: "OK".into(),
                            action: Action::None,
                            input: false,
                        })
                    }
                    Delivery::Inspector(generation, message) => {
                        if generation != s.inspector_generation {
                            continue;
                        }
                        if let Some(d) = &mut s.dialog {
                            if d.title.ends_with(" Properties") {
                                d.message = message;
                            }
                        }
                    }
                    Delivery::Power(result) => match result {
                        Ok((source, previous, target)) => {
                            if target == 1 {
                                s.prefs.restore.insert(source, previous);
                            } else {
                                s.prefs.restore.remove(&source);
                            }
                            s.prefs.save();
                        }
                        Err(e) => {
                            if !e.contains("(-128)") {
                                s.dialog = Some(Dialog {
                                    title: "Power mode could not be changed".into(),
                                    message: e,
                                    ok: "OK".into(),
                                    action: Action::None,
                                    input: false,
                                });
                            }
                        }
                    },
                    _ => {}
                }
                changed = true;
            }
            let info = NSProcessInfo::processInfo();
            let low = info.isLowPowerModeEnabled();
            if low != s.power_on {
                s.power_on = low;
                changed = true;
            }
            if changed && s.menus.is_empty() && s.dialog.is_none() && s.drag.is_none() {
                s.rebuild();
            }
            if s.last_save.elapsed() > Duration::from_secs(30) {
                let prefs = s.prefs.clone();
                let history = s.history.entries.clone();
                let times = self.ivars().timings.borrow().clone();
                let draws = s.redraw_ms.clone();
                std::thread::spawn(move || {
                    prefs.save();
                    if let Ok(json) = serde_json::to_vec(&history) {
                        let _ = std::fs::write(support().join("rust-history.json"), json);
                    }
                    if let Ok(json) = serde_json::to_vec_pretty(
                        &serde_json::json!({"interactions":times,"draw_ms":draws}),
                    ) {
                        let _ = std::fs::write(support().join("rust-timings.json"), json);
                    }
                });
                s.last_save = Instant::now();
            }
        }
        if changed || icons_changed {
            self.redraw();
        }
    }
    fn drag_scroll(&self, a: &Action, x: f64, y: f64, first: bool) {
        let mut s = self.ivars().state.borrow_mut();
        let Some((_, sx, sy, start)) = s.drag.clone() else {
            return;
        };
        match a {
            Action::ScrollV => {
                let top = if s.page == 7 { 48. } else { s.table_top() };
                let max = if s.page == 7 {
                    s.max_scroll()
                } else {
                    s.max_scroll()
                };
                let view = s.height - top - 15.;
                let thumb = (view / (view + max) * view).max(28.);
                if first {
                    let current_y = top + s.scroll / max.max(1.) * (view - thumb);
                    if y < current_y {
                        s.scroll = (s.scroll - view).max(0.)
                    } else if y > current_y + thumb {
                        s.scroll = (s.scroll + view).min(max);
                    }
                    let offset = s.scroll;
                    s.drag = Some((a.clone(), x, y, offset));
                } else {
                    s.scroll = (start + (y - sy) * max / (view - thumb).max(1.)).clamp(0., max);
                }
            }
            Action::ScrollH => {
                let view = s.width - s.sidebar() - 15.;
                let total: f64 = s.columns.iter().map(|c| c.width).sum();
                let max = (total - view).max(0.);
                let thumb = (view / total * view).max(30.);
                if first {
                    let current_x = s.sidebar() + s.hscroll / max.max(1.) * (view - thumb);
                    if x < current_x {
                        s.hscroll = (s.hscroll - view).max(0.)
                    } else if x > current_x + thumb {
                        s.hscroll = (s.hscroll + view).min(max);
                    }
                    let offset = s.hscroll;
                    s.drag = Some((a.clone(), x, y, offset));
                } else {
                    s.hscroll = (start + (x - sx) * max / (view - thumb).max(1.)).clamp(0., max);
                }
            }
            Action::ResizeColumn(i) => {
                s.columns[*i].width = (start + x - sx).clamp(55., 900.);
                let key = format!("{}:{}", s.page, s.columns[*i].key);
                let width = s.columns[*i].width;
                s.prefs.widths.insert(key, width);
            }
            _ => {}
        }
        drop(s);
        self.redraw();
    }
    fn key(&self, e: &NSEvent) -> bool {
        let key = e.keyCode();
        if key == 15
            && e.modifierFlags()
                .contains(NSEventModifierFlags::Command | NSEventModifierFlags::Shift)
        {
            self.toggle_recording();
            return true;
        }
        let flags = e.modifierFlags();
        let cmd = flags.contains(NSEventModifierFlags::Command)
            || flags.contains(NSEventModifierFlags::Control);
        let alt = flags.contains(NSEventModifierFlags::Option);
        let text = e
            .charactersIgnoringModifiers()
            .map(|s| s.to_string().to_lowercase())
            .unwrap_or_default();
        if cmd && text == "c" && self.ivars().state.borrow().page == 1 {
            self.dispatch(Action::Copy);
            return true;
        }
        if cmd && text == "f" {
            self.focus_search();
            return true;
        }
        if cmd && text == "q" {
            self.dispatch(Action::Quit);
            return true;
        }
        if cmd && text == "n" || alt && text == "n" {
            self.dispatch(Action::Run);
            return true;
        }
        if alt && text == "e" {
            self.dispatch(Action::End);
            return true;
        }
        if alt && key == 118 {
            self.dispatch(Action::Close);
            return true;
        }
        if alt && key == 49 {
            let mut s = self.ivars().state.borrow_mut();
            open_menu(&mut s, system_menu(), 8., 36.);
            drop(s);
            self.redraw();
            return true;
        }
        if cmd && key == 48 {
            let next = {
                let s = self.ivars().state.borrow();
                (s.page
                    + if flags.contains(NSEventModifierFlags::Shift) {
                        7
                    } else {
                        1
                    })
                    % 8
            };
            self.dispatch(Action::Page(next));
            return true;
        }
        if cmd {
            if let Ok(n) = text.parse::<usize>() {
                if (1..=8).contains(&n) {
                    self.dispatch(Action::Page(n - 1));
                    return true;
                }
            }
        }
        if key == 96 {
            self.dispatch(Action::Refresh);
            return true;
        }
        let mut s = self.ivars().state.borrow_mut();
        if s.dialog.is_some() {
            drop(s);
            if key == 53 {
                self.dispatch(Action::DialogCancel)
            } else if key == 36 {
                self.dispatch(Action::DialogOk)
            } else {
                return false;
            }
            return true;
        }
        if !s.menus.is_empty() {
            let m = s.menus.last_mut().unwrap();
            match key {
                53 => {
                    s.menus.clear();
                }
                123 => {
                    s.menus.pop();
                }
                125 | 126 => {
                    let len = m.items.len();
                    let mut i = m.selected.unwrap_or(if key == 125 { len - 1 } else { 0 });
                    for _ in 0..len {
                        i = if key == 125 {
                            (i + 1) % len
                        } else {
                            (i + len - 1) % len
                        };
                        if m.items[i].enabled && !m.items[i].title.is_empty() {
                            m.selected = Some(i);
                            break;
                        }
                    }
                }
                36 | 124 => {
                    if let Some(index) = m.selected {
                        let depth = s.menus.len() - 1;
                        drop(s);
                        self.dispatch(Action::Option(format!("menu:{depth}:{index}")));
                        return true;
                    }
                }
                _ => {}
            }
            drop(s);
            self.redraw();
            return true;
        }
        if key == 48 {
            let actions = s
                .hits
                .iter()
                .filter(|h| {
                    h.enabled
                        && !matches!(
                            h.action,
                            Action::None
                                | Action::ScrollH
                                | Action::ScrollV
                                | Action::ResizeColumn(_)
                                | Action::Select(_)
                                | Action::Expand(_)
                                | Action::Menu(_)
                        )
                })
                .map(|h| h.action.clone())
                .collect::<Vec<_>>();
            if !actions.is_empty() {
                let current = actions.iter().position(|a| a == &s.focus);
                let next = if flags.contains(NSEventModifierFlags::Shift) {
                    current
                        .map(|i| (i + actions.len() - 1) % actions.len())
                        .unwrap_or(actions.len() - 1)
                } else {
                    current.map(|i| (i + 1) % actions.len()).unwrap_or(0)
                };
                s.focus = actions[next].clone();
            }
            drop(s);
            if let Some(w) = self.window() {
                w.makeFirstResponder(Some(self));
            }
            self.redraw();
            return true;
        }
        if (key == 36 || key == 49) && s.focus != Action::None {
            let a = s.focus.clone();
            drop(s);
            self.dispatch(a);
            return true;
        }
        match key {
            53 => {
                if s.graph_only {
                    s.graph_only = false
                } else {
                    s.query.clear();
                    if let Some(f) = self.ivars().search.get() {
                        f.setStringValue(ns_string!(""));
                    }
                    s.rebuild();
                }
            }
            125 | 126 => {
                let len = s.rows.len();
                if len == 0 {
                    return true;
                }
                let current = s
                    .selected
                    .as_ref()
                    .and_then(|id| s.rows.iter().position(|r| &r.id == id));
                let mut i = current.unwrap_or(if key == 125 { len - 1 } else { 0 });
                for _ in 0..len {
                    i = if key == 125 {
                        (i + 1) % len
                    } else {
                        (i + len - 1) % len
                    };
                    if !s.rows[i].section {
                        s.selected = Some(s.rows[i].id.clone());
                        break;
                    }
                }
                s.selected_visible();
            }
            123 | 124 => {
                if let Some(r) = s.current().cloned() {
                    if key == 124 {
                        s.expanded.insert(r.id);
                    } else {
                        s.expanded.remove(&r.id);
                    }
                    s.rebuild();
                }
            }
            51 | 117 => {
                drop(s);
                self.dispatch(Action::End);
                return true;
            }
            36 => {
                drop(s);
                self.dispatch(Action::Properties);
                return true;
            }
            116 => s.scroll = (s.scroll - s.height * 0.7).max(0.),
            121 => {
                s.scroll += s.height * 0.7;
                s.clamp_scroll();
            }
            115 => s.scroll = 0.,
            119 => s.scroll = s.max_scroll(),
            _ => return false,
        }
        drop(s);
        self.redraw();
        true
    }
    pub fn dispatch(&self, action: Action) {
        let start = Instant::now();
        self.act(action.clone());
        self.ivars()
            .timings
            .borrow_mut()
            .push_back((format!("{action:?}"), start.elapsed().as_secs_f64() * 1000.));
        if self.ivars().timings.borrow().len() > 2048 {
            self.ivars().timings.borrow_mut().pop_front();
        }
        self.redraw();
        self.displayIfNeeded();
        unsafe {
            NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
        }
        self.ivars().timings.borrow_mut().push_back((
            format!("paint:{action:?}"),
            start.elapsed().as_secs_f64() * 1000.,
        ));
    }
    fn act(&self, action: Action) {
        if self.ivars().state.borrow().dialog.is_some()
            && !matches!(
                action,
                Action::DialogOk | Action::DialogCancel | Action::Quit | Action::Close
            )
            && action != Action::Option("copy-properties".into())
        {
            return;
        }

        if action == Action::Quit || action == Action::Close {
            self.ivars().state.borrow().save();
            self.ivars().state.borrow().shared.lock().unwrap().stop = true;
            unsafe {
                NSApplication::sharedApplication(self.mtm()).terminate(None);
            }
            return;
        }
        if [Action::Minimize, Action::Maximize].contains(&action) {
            if let Some(w) = self.window() {
                if action == Action::Minimize {
                    w.miniaturize(None);
                    if self.ivars().state.borrow().prefs.hide {
                        NSApplication::sharedApplication(self.mtm()).hide(None);
                    }
                } else {
                    let previous = self.ivars().restore.borrow_mut().take();
                    if let Some(previous) = previous {
                        w.setFrame_display(previous, true);
                    } else if let Some(screen) = w.screen() {
                        *self.ivars().restore.borrow_mut() = Some(w.frame());
                        w.setFrame_display(screen.visibleFrame(), true);
                    }
                }
            }
            return;
        }
        let mut s = self.ivars().state.borrow_mut();
        match action{
 Action::None=>{s.menus.clear();},Action::Page(n)=>{s.focus=Action::None;if s.page != n {s.set_page(n)}},Action::Resource(n)=>{s.resource=n;s.menus.clear();},Action::Collapse=>s.collapsed=!s.collapsed,
 Action::Sort(k)=>{if s.sort==k{s.ascending=!s.ascending}else{s.ascending=!s.columns.iter().find(|c|c.key==k).is_some_and(|c|c.numeric);s.sort=k;}s.sort_rows();},Action::Select(id)=>{s.selections.clear();s.selected=Some(id);s.menus.clear();},Action::Expand(id)=>{if !s.expanded.remove(&id){s.expanded.insert(id);}s.rebuild();},Action::Run=>{s.dialog=Some(Dialog{title:"Create new task".into(),message:"Type the name of an application or its full path.".into(),ok:"OK".into(),action:Action::Option("run-confirm".into()),input:true});if let Some(f)=self.ivars().input.get(){f.setStringValue(ns_string!(""));}drop(s);self.layout_fields();if let(Some(f),Some(w))=(self.ivars().input.get(),self.window()){w.makeFirstResponder(Some(f));}return},
 Action::End=>{if !s.can_end(){return}let name=format!("{} ({} processes)",s.current().unwrap().name,s.selected_processes().len());s.dialog=Some(Dialog{title:format!("End {name}?"),message:"Unsaved data may be lost. The selected application\nand its grouped processes will be terminated.".into(),ok:"End task".into(),action:Action::Signal(libc::SIGTERM),input:false});s.menus.clear();},
 Action::Signal(signal)=>{let processes=s.selected_processes().into_iter().cloned().collect::<Vec<_>>();if processes.is_empty(){return}s.busy=true;let shared=s.shared.clone();std::thread::spawn(move||{let result=processes.iter().try_for_each(|p|p.revalidate()).and_then(|_|processes.iter().try_for_each(|p|p.signal(signal))).map(|_|String::new());let mut q=shared.lock().unwrap();q.results.push_back(Delivery::Operation(result));q.refresh=true;});},
 Action::Priority(n)=>{if let Some(p)=s.process().cloned(){let shared=s.shared.clone();std::thread::spawn(move||{let result=p.priority(n).map(|_|String::new());shared.lock().unwrap().results.push_back(Delivery::Operation(result));});}},
 Action::Efficiency=>{s.menus.clear();s.dialog=Some(Dialog{title:if s.power_on{"Turn off Low Power Mode?"}else{"Turn on Low Power Mode?"}.into(),message:"Efficiency mode controls this Mac's Low Power Mode.\nIt changes the current power-source profile for the\nwhole Mac. macOS will ask for administrator approval.\nThe other power-source profile will stay unchanged.".into(),ok:if s.power_on{"Restore"}else{"Turn on"}.into(),action:Action::Option("power-confirm".into()),input:false});},
 Action::DialogCancel=>{s.dialog=None;s.dialog_scroll=0.;},Action::DialogOk=>{let next=s.dialog.take().map(|d|d.action).unwrap_or(Action::None);drop(s);self.act(next);return},
 Action::View=>{let items=view_menu(&s);let x=(s.width-270.).max(0.);open_menu(&mut s,items,x,90.);},Action::Menu(_)=>{},Action::Option(value)=>{if let Some((depth,index))=parse_menu(&value){if let Some(menu)=s.menus.get(depth){if let Some(item)=menu.items.get(index).cloned(){if !item.enabled{return}if !item.children.is_empty(){let x=if menu.x+504.>s.width{(menu.x-252.).max(0.)}else{menu.x+252.};let y=menu.y.min((s.height-menu_height(&item.children)).max(0.));s.menus.truncate(depth+1);s.menus.push(Menu{x,y,items:item.children,selected:None});}else{s.menus.clear();drop(s);self.act(item.action);return}}}return}
  if value=="search-clear"{s.query.clear();if let Some(f)=self.ivars().search.get(){f.setStringValue(ns_string!(""));}s.rebuild();}
  else if value=="run-confirm"{let text=self.ivars().input.get().map(|f|f.stringValue().to_string()).unwrap_or_default();let text=text.trim().to_string();if text.is_empty(){return}let shared=s.shared.clone();std::thread::spawn(move||{let result=if text.starts_with('/'){services::command("/usr/bin/open",&[&text],Duration::from_secs(5))}else{services::command("/usr/bin/open",&["-a",&text],Duration::from_secs(5))};shared.lock().unwrap().results.push_back(Delivery::Operation(result));});}
  else if value=="power-confirm"{s.busy=true;let restore=s.prefs.restore.clone();let shared=s.shared.clone();std::thread::spawn(move||{let result=(||{let source=power::source();let profiles=power::read();let profile=*profiles.get(&source).ok_or("Low Power Mode is unavailable for this power source.")?;let target=if profile.mode==1{restore.get(&source).copied().filter(|v|*v!=1).unwrap_or(0)}else{1};power::set(&source,profile,target)?;Ok((source,profile.mode,target))})();shared.lock().unwrap().results.push_back(Delivery::Power(result));});}
  else if value=="force" {if s.can_end(){let n=s.selected_processes().len();s.dialog=Some(Dialog{title:"Force quit selected processes?".into(),message:format!("{n} process(es) will stop immediately.\nUnsaved data may be lost."),ok:"Force quit".into(),action:Action::Signal(libc::SIGKILL),input:false});}}
  else if value=="copy-properties" {if let Some(d)=&s.dialog{let pb=NSPasteboard::generalPasteboard();pb.clearContents();unsafe{pb.setString_forType(&NSString::from_str(&d.message),NSPasteboardTypeString);}}}
  else if value=="copy-pid" || value=="copy-path" {if let Some(p)=s.process(){let text=if value=="copy-pid"{p.raw.pid.to_string()}else{p.path.clone()};let pb=NSPasteboard::generalPasteboard();pb.clearContents();unsafe{pb.setString_forType(&NSString::from_str(&text),NSPasteboardTypeString);}}}
  else if value=="manage-users"{open_url("x-apple.systempreferences:com.apple.Users-Groups-Settings.extension");}
  else if value=="feedback"{open_url("https://github.com/hotredsam/task-manager-macos/issues/new");}
  else if value=="open-services"{open_url("x-apple.systempreferences:com.apple.LoginItems-Settings.extension");}
  else if value=="memory-percent"{s.memory_percent=true;s.rebuild();}else if value=="memory-values"{s.memory_percent=false;s.rebuild();}
  else if let Some(key)=value.strip_prefix("column:"){let page=s.page;let defaults=columns(page).iter().filter(|c|!s.columns.iter().any(|v|v.key==c.key)).map(|c|c.key.clone()).collect();let hidden=s.prefs.hidden.entry(page).or_insert(defaults);if !hidden.remove(key){hidden.insert(key.into());}s.reset_columns();s.rebuild();}
  else if let Some(n)=value.strip_prefix("speed:").and_then(|n|n.parse::<u64>().ok()){s.prefs.speed=n;s.shared.lock().unwrap().speed=n;s.history.reset_baseline();}
  else if let Some(n)=value.strip_prefix("start:").and_then(|n|n.parse::<usize>().ok()){s.prefs.start=n.min(7);}
  else if value=="theme:light"{s.prefs.dark=false;s.prefs.system_theme=false;}else if value=="theme:dark"{s.prefs.dark=true;s.prefs.system_theme=false;}else if value=="theme:system"{s.prefs.system_theme=true;s.prefs.dark=NSUserDefaults::standardUserDefaults().stringForKey(ns_string!("AppleInterfaceStyle")).is_some();}
  else if let Some(n)=value.strip_prefix("history:").and_then(|n|n.parse::<usize>().ok()){s.prefs.graph_seconds=n.clamp(30,300);}
  else if value=="units:binary"{s.prefs.binary=true;s.rebuild();}else if value=="units:decimal"{s.prefs.binary=false;s.rebuild();}
  else if let Some(a)=value.strip_prefix("service-confirm:"){if let Some(i)=s.current().and_then(|r|r.service){let service=s.services[i].clone();let a=a.to_string();let shared=s.shared.clone();s.busy=true;std::thread::spawn(move||{let result=services::change(&service,&a);let mut q=shared.lock().unwrap();q.results.push_back(Delivery::Operation(result));q.scan=true;});}}
  s.prefs.save();
 },
 Action::Service(action)=>{if let Some(i)=s.current().and_then(|r|r.service){if s.services[i].mutable{s.dialog=Some(Dialog{title:format!("{} service?",action.to_uppercase()),message:format!("{}\nThis changes your user LaunchAgent.\nThe operation can affect its running application.",s.services[i].label),ok:action.clone(),action:Action::Option(format!("service-confirm:{action}")),input:false});}}},
 Action::Refresh=>{let mut q=s.shared.lock().unwrap();q.refresh=true;q.scan=true;},Action::ResetHistory=>{s.history=Default::default();s.rebuild();},Action::Logical(on)=>s.prefs.logical=on,Action::Kernel=>s.prefs.kernel=!s.prefs.kernel,Action::Summary=>s.summary=!s.summary,Action::GraphOnly=>s.graph_only=!s.graph_only,
 Action::Copy=>{let text=if s.page==1{format!("{}\nCPU: {:0.1}%\nMemory: {} / {}\nLogical processors: {}",model::cstr(&s.system.raw.brand),s.system.cpu,model::bytes(s.system.used()as f64,s.prefs.binary),model::bytes(s.system.raw.ram as f64,s.prefs.binary),s.system.raw.logical)}else{s.current().map(|r|format!("{}\n{}",r.name,s.columns.iter().map(|c|format!("{}: {}",c.title,s.row_value(r,&c.key))).collect::<Vec<_>>().join("\n"))).unwrap_or_default()};let pb=NSPasteboard::generalPasteboard();pb.clearContents();unsafe{pb.setString_forType(&NSString::from_str(&text),NSPasteboardTypeString);}},
 Action::Properties=>{s.inspector_generation=s.inspector_generation.wrapping_add(1);let generation=s.inspector_generation;s.dialog_scroll=0.;if let Some(r)=s.current().cloned(){if let Some(process)=s.process().cloned(){let shared=s.shared.clone();std::thread::spawn(move||{let message=process_details(&process);shared.lock().unwrap().results.push_back(Delivery::Inspector(generation,message));});}let message=if let Some(i)=r.service{let q=&s.services[i];format!("Name: {}\nStatus: {}\nDomain: {}\nProgram: {}\nConfiguration: {}",q.label,q.status(),q.domain,q.program,q.path)}else if let Some(p)=s.process(){format!("Name: {}\nPID: {}  Parent PID: {}\nUser: {}  Status: {}\nCPU: {:0.1}%  Memory: {}\nPath: {}",p.name,p.raw.pid,p.raw.ppid,p.user,p.status(),p.cpu,model::bytes(p.raw.memory as f64,s.prefs.binary),p.path)}else{r.name.clone()};s.dialog=Some(Dialog{title:format!("{} Properties",r.name),message,ok:"OK".into(),action:Action::None,input:false});}},
 Action::Reveal=>{let path=s.process().map(|p|p.path.clone()).or_else(||s.current().and_then(|r|r.service).map(|i|s.services[i].path.clone()));if let Some(path)=path{std::thread::spawn(move||{let _=services::command("/usr/bin/open",&["-R",&path],Duration::from_secs(5));});}},Action::SearchOnline=>{if let Some(r)=s.current(){let encoded=r.name.bytes().map(|b|if b.is_ascii_alphanumeric()||b==b'-'{(b as char).to_string()}else{format!("%{b:02X}")}).collect::<String>();open_url(&format!("https://www.bing.com/search?q={encoded}"));}},
 Action::GoDetails=>{let pid=s.process().map(|p|p.id()).or_else(||s.current().and_then(|r|r.service).and_then(|i|s.services[i].pid).and_then(|pid|s.records.iter().find(|p|p.raw.pid==pid).map(|p|p.id())));s.set_page(5);s.selected=pid;s.selected_visible();},
 Action::Switch=>{if s.page==2{if let Some(row)=s.current(){let path=row.icon.clone();std::thread::spawn(move||{let _=services::command("/usr/bin/open",&[&path],Duration::from_secs(5));});}}else if let Some(p)=s.process(){if !p.app.is_empty(){let path=p.app.clone();std::thread::spawn(move||{let _=services::command("/usr/bin/open",&[&path],Duration::from_secs(5));});if s.prefs.minimize{if let Some(w)=self.window(){w.miniaturize(None);}}}}},
 Action::Snap(n)=>{if let Some(w)=self.window(){if let Some(screen)=w.screen(){let mut r=screen.visibleFrame();if self.ivars().restore.borrow().is_none(){*self.ivars().restore.borrow_mut()=Some(w.frame())}r.size.width/=2.;if n==1{r.origin.x+=r.size.width;}w.setFrame_display(r,true);}}},
 Action::Setting(key)=>{match key.as_str(){"top"=>{s.prefs.top=!s.prefs.top;if let Some(w)=self.window(){w.setLevel(if s.prefs.top{3}else{0});}},"minimize"=>s.prefs.minimize=!s.prefs.minimize,"hide"=>s.prefs.hide=!s.prefs.hide,"history-all"=>{s.prefs.history_all=!s.prefs.history_all;s.rebuild();},"login"=>{drop(s);self.change_login();return;},"grouped"=>{s.prefs.grouped=!s.prefs.grouped;s.rebuild();},_=>{let items=setting_menu(&s,&key);let hit=s.hits.iter().find(|h|h.action==Action::Setting(key.clone()));let(x,y)=hit.map(|h|(h.rect[0],h.rect[1]+h.rect[3])).unwrap_or((s.sidebar()+32.,140.));open_menu(&mut s,items,x,y);}}s.prefs.save();},
 Action::About=>s.dialog=Some(Dialog{title:"Task Manager".into(),message:"Version 2.0 · Rust + native AppKit\nBuilt for Apple silicon · macOS 14 or later\nOpen source under the MIT license.\nWindows visual references and third-party icon\nrights are documented in the source repository.".into(),ok:"OK".into(),action:Action::None,input:false}),_=>{}}
    }
}
fn open_url(url: &str) {
    let text = url.to_string();
    std::thread::spawn(move || {
        let _ = services::command("/usr/bin/open", &[&text], Duration::from_secs(5));
    });
}
fn parse_menu(s: &str) -> Option<(usize, usize)> {
    let p: Vec<_> = s.strip_prefix("menu:")?.split(':').collect();
    Some((p.first()?.parse().ok()?, p.get(1)?.parse().ok()?))
}
fn menu_height(items: &[MenuItem]) -> f64 {
    8. + items
        .iter()
        .map(|i| if i.title.is_empty() { 9. } else { 30. })
        .sum::<f64>()
}
fn open_menu(s: &mut State, items: Vec<MenuItem>, x: f64, y: f64) {
    let x = x.clamp(0., (s.width - 256.).max(0.));
    let y = y.clamp(0., (s.height - menu_height(&items)).max(0.));
    s.menus = vec![Menu {
        x,
        y,
        items,
        selected: None,
    }];
}
fn system_menu() -> Vec<MenuItem> {
    vec![
        MenuItem::new("Restore", Action::Maximize),
        MenuItem::new("Minimize", Action::Minimize),
        MenuItem::new("Maximize", Action::Maximize),
        MenuItem::sep(),
        MenuItem::new("Snap left", Action::Snap(0)),
        MenuItem::new("Snap right", Action::Snap(1)),
        MenuItem::sep(),
        MenuItem::new("Close                  Alt+F4", Action::Close),
    ]
}
fn graph_menu(s: &State) -> Vec<MenuItem> {
    let mut items = Vec::new();
    if s.resource == 0 {
        items.push(MenuItem::sub(
            "Change graph to",
            vec![
                MenuItem::check(
                    "Overall utilization",
                    Action::Logical(false),
                    !s.prefs.logical,
                ),
                MenuItem::check("Logical processors", Action::Logical(true), s.prefs.logical),
                MenuItem::disabled("NUMA nodes"),
            ],
        ));
        items.push(MenuItem::check(
            "Show kernel times",
            Action::Kernel,
            s.prefs.kernel,
        ));
    }
    items.push(MenuItem::check(
        "Graph summary view",
        Action::GraphOnly,
        s.graph_only,
    ));
    items.push(MenuItem::sub(
        "View",
        ["CPU", "Memory", "Disk 0", "Network", "GPU 0"]
            .iter()
            .enumerate()
            .map(|(i, t)| MenuItem::check(t, Action::Resource(i), s.resource == i))
            .collect(),
    ));
    items.push(MenuItem::sep());
    items.push(MenuItem::new(
        "Copy                         Ctrl+C",
        Action::Copy,
    ));
    items
}

fn view_menu(s: &State) -> Vec<MenuItem> {
    let mut v = vec![
        MenuItem::new("Run new task", Action::Run),
        MenuItem::check("Efficiency mode", Action::Efficiency, s.power_on),
        MenuItem::new("Refresh now                 F5", Action::Refresh),
        MenuItem::sub("Update speed", setting_menu(s, "speed")),
    ];
    if s.page == 1 {
        v.extend(graph_menu(s))
    } else {
        v.push(MenuItem::sub(
            "Select columns",
            columns(s.page)
                .iter()
                .map(|c| {
                    MenuItem::check(
                        &c.title,
                        Action::Option(format!("column:{}", c.key)),
                        s.columns.iter().any(|v| v.key == c.key),
                    )
                })
                .collect(),
        ));
    }
    v
}
fn row_menu(s: &State) -> Vec<MenuItem> {
    let Some(r) = s.current() else {
        return view_menu(s);
    };
    if s.page == 6 || s.page == 3 {
        let service = r.service.map(|i| &s.services[i]);
        let mutable = service.is_some_and(|s| s.mutable);
        let mut v = vec![];
        for (t, a) in if s.page == 3 {
            vec![("Enable", "enable"), ("Disable", "disable")]
        } else {
            vec![("Start", "start"), ("Stop", "stop"), ("Restart", "restart")]
        } {
            let mut i = MenuItem::new(t, Action::Service(a.into()));
            i.enabled = mutable;
            v.push(i)
        }
        v.extend([
            MenuItem::sep(),
            MenuItem::new("Open Services", Action::Option("open-services".into())),
            MenuItem::new("Search online", Action::SearchOnline),
            MenuItem::new("Go to details", Action::GoDetails),
            MenuItem::new("Properties", Action::Properties),
        ]);
        return v;
    }
    let mut expand = MenuItem::new(
        if s.expanded.contains(&r.id) {
            "Collapse"
        } else {
            "Expand"
        },
        Action::Expand(r.id.clone()),
    );
    expand.enabled = r.group;
    let mut switch = MenuItem::new("Switch to", Action::Switch);
    switch.enabled = s.process().is_some_and(|p| !p.app.is_empty());
    let mut end = MenuItem::new("End task", Action::End);
    end.enabled = s.can_end();
    let mut v = vec![
        expand,
        switch,
        end,
        MenuItem::sub(
            "Resource values",
            vec![MenuItem::sub(
                "Memory",
                vec![
                    MenuItem::check(
                        "Percents",
                        Action::Option("memory-percent".into()),
                        s.memory_percent,
                    ),
                    MenuItem::check(
                        "Values",
                        Action::Option("memory-values".into()),
                        !s.memory_percent,
                    ),
                ],
            )],
        ),
        MenuItem::new("Provide feedback", Action::Option("feedback".into())),
        MenuItem::sep(),
        MenuItem::check("Efficiency mode", Action::Efficiency, s.power_on),
        MenuItem::disabled("Debug"),
        MenuItem::disabled("Create dump file"),
        MenuItem::sep(),
        MenuItem::new("Go to details", Action::GoDetails),
        MenuItem::new("Open file location", Action::Reveal),
        MenuItem::new("Search online", Action::SearchOnline),
        MenuItem::new("Properties", Action::Properties),
    ];
    let mut force = MenuItem::new("Force quit", Action::Option("force".into()));
    force.enabled = s.can_end();
    v.push(MenuItem::sub(
        "More",
        vec![
            force,
            MenuItem::new("Copy details", Action::Copy),
            MenuItem::new("Copy PID", Action::Option("copy-pid".into())),
            MenuItem::new("Copy path", Action::Option("copy-path".into())),
        ],
    ));
    if s.page == 5 {
        let priority = MenuItem::sub(
            "Set priority",
            [("Normal", 0), ("Below normal", 10), ("Low", 19)]
                .iter()
                .map(|(t, n)| {
                    let mut i = MenuItem::new(t, Action::Priority(*n));
                    i.enabled = s
                        .process()
                        .is_some_and(|p| !p.protected() && *n >= p.raw.nice);
                    i
                })
                .collect(),
        );
        v.insert(3, priority);
        v.insert(4, MenuItem::disabled("Set affinity"));
    }
    v
}
fn setting_menu(s: &State, key: &str) -> Vec<MenuItem> {
    match key {
        "start" => PAGES
            .iter()
            .enumerate()
            .map(|(i, t)| {
                MenuItem::check(t, Action::Option(format!("start:{i}")), s.prefs.start == i)
            })
            .collect(),
        "speed" => [("High", 1), ("Normal", 2), ("Low", 4), ("Paused", 0)]
            .iter()
            .map(|(t, n)| {
                MenuItem::check(t, Action::Option(format!("speed:{n}")), s.prefs.speed == *n)
            })
            .collect(),
        "theme" => ["Light", "Dark", "Use system setting"]
            .iter()
            .zip(["light", "dark", "system"])
            .map(|(t, v)| MenuItem::new(t, Action::Option(format!("theme:{v}"))))
            .collect(),
        "history" => [30, 60, 120, 300]
            .iter()
            .map(|n| {
                MenuItem::check(
                    &format!("{n} seconds"),
                    Action::Option(format!("history:{n}")),
                    s.prefs.graph_seconds == *n,
                )
            })
            .collect(),
        "units" => vec![
            MenuItem::check(
                "Decimal",
                Action::Option("units:decimal".into()),
                !s.prefs.binary,
            ),
            MenuItem::check(
                "Binary",
                Action::Option("units:binary".into()),
                s.prefs.binary,
            ),
        ],
        _ => vec![],
    }
}
#[derive(Default)]
struct DelegateIvars {
    window: OnceCell<Retained<NSWindow>>,
    canvas: OnceCell<Retained<Canvas>>,
}
define_class!(
    #[unsafe(super=NSObject)]
    #[thread_kind=MainThreadOnly]
    #[ivars=DelegateIvars]
    struct Delegate;
    unsafe impl NSObjectProtocol for Delegate {}
    unsafe impl NSApplicationDelegate for Delegate {
        #[unsafe(method(applicationDidFinishLaunching:))]
        fn launched(&self, _n: &NSNotification) {
            let mtm = self.mtm();
            let app = NSApplication::sharedApplication(mtm);
            let canvas = Canvas::new(mtm);
            let window = unsafe {
                NSWindow::initWithContentRect_styleMask_backing_defer(
                    NSWindow::alloc(mtm),
                    rect(0., 0., 1120., 720.),
                    NSWindowStyleMask::Titled
                        | NSWindowStyleMask::Closable
                        | NSWindowStyleMask::Miniaturizable
                        | NSWindowStyleMask::Resizable
                        | NSWindowStyleMask::FullSizeContentView,
                    NSBackingStoreType::Buffered,
                    false,
                )
            };
            unsafe {
                window.setReleasedWhenClosed(false);
                window.setContentMinSize(NSSize::new(800., 560.));
            }
            window.setTitle(ns_string!("Task Manager"));
            window.setTitleVisibility(NSWindowTitleVisibility::Hidden);
            window.setTitlebarAppearsTransparent(true);
            for b in [
                NSWindowButton::CloseButton,
                NSWindowButton::MiniaturizeButton,
                NSWindowButton::ZoomButton,
            ] {
                if let Some(btn) = window.standardWindowButton(b) {
                    btn.setHidden(true)
                }
            }
            window.setContentView(Some(&canvas));
            window.setDelegate(Some(ProtocolObject::from_ref(self)));
            window.setAcceptsMouseMovedEvents(true);
            window.center();
            window.setFrameAutosaveName(ns_string!("TaskManagerRustWindow"));
            window.setFrameUsingName(ns_string!("TaskManagerRustWindow"));
            window.setLevel(if canvas.ivars().state.borrow().prefs.top {
                3
            } else {
                0
            });
            // Allocate and initialize AppKit's shared field editor before the first click.
            if let Some(search) = canvas.ivars().search.get() {
                unsafe {
                    let _ = window.fieldEditor_forObject(true, Some(search));
                }
                window.makeFirstResponder(Some(search));
            }
            window.makeKeyAndOrderFront(None);
            window.makeFirstResponder(Some(&canvas));
            install_menu(&canvas, mtm);
            app.setActivationPolicy(NSApplicationActivationPolicy::Regular);
            #[allow(deprecated)]
            app.activateIgnoringOtherApps(true);
            self.ivars().window.set(window).unwrap();
            self.ivars().canvas.set(canvas).ok();
        }
        #[unsafe(method(applicationShouldTerminateAfterLastWindowClosed:))]
        fn terminate_after(&self, _app: &NSApplication) -> bool {
            true
        }
        #[unsafe(method(applicationWillTerminate:))]
        fn will_terminate(&self, _n: &NSNotification) {
            if let Some(c) = self.ivars().canvas.get() {
                c.ivars().state.borrow().save();
                c.ivars().state.borrow().shared.lock().unwrap().stop = true;
            }
        }
        #[unsafe(method(applicationShouldHandleReopen:hasVisibleWindows:))]
        fn reopen(&self, _app: &NSApplication, _visible: bool) -> bool {
            if let Some(w) = self.ivars().window.get() {
                w.deminiaturize(None);
                w.makeKeyAndOrderFront(None);
            }
            true
        }
    }
    unsafe impl NSWindowDelegate for Delegate {}
);
fn install_menu(canvas: &Canvas, mtm: MainThreadMarker) {
    let app = NSApplication::sharedApplication(mtm);
    let menu = NSMenu::new(mtm);
    for (title, items) in [
        (
            "Task Manager",
            vec![
                ("About Task Manager", "", 13),
                ("Quit Task Manager", "q", 14),
            ],
        ),
        ("File", vec![("Run new task", "n", 10)]),
        (
            "View",
            vec![
                ("Processes", "1", 0),
                ("Performance", "2", 1),
                ("App history", "3", 2),
                ("Startup apps", "4", 3),
                ("Users", "5", 4),
                ("Details", "6", 5),
                ("Services", "7", 6),
                ("Settings", "8", 7),
                ("Refresh now", "r", 11),
                ("Search", "f", 15),
            ],
        ),
    ] {
        let item = NSMenuItem::new(mtm);
        let sub = NSMenu::initWithTitle(NSMenu::alloc(mtm), &NSString::from_str(title));
        for (label, key, tag) in items {
            let m = unsafe {
                NSMenuItem::initWithTitle_action_keyEquivalent(
                    NSMenuItem::alloc(mtm),
                    &NSString::from_str(label),
                    Some(sel!(menuAction:)),
                    &NSString::from_str(key),
                )
            };
            m.setTag(tag);
            unsafe {
                m.setTarget(Some(canvas));
            }
            sub.addItem(&m);
        }
        item.setSubmenu(Some(&sub));
        menu.addItem(&item);
    }
    app.setMainMenu(Some(&menu));
}
#[link(name = "CoreText", kind = "framework")]
extern "C" {
    fn CTFontManagerRegisterFontsForURL(
        url: *const AnyObject,
        scope: u32,
        error: *mut *mut std::ffi::c_void,
    ) -> bool;
}
pub fn run() {
    let mtm = MainThreadMarker::new().expect("AppKit requires the main thread");
    let app = NSApplication::sharedApplication(mtm);
    if let Some(path) = NSBundle::mainBundle().resourcePath() {
        let folder = format!("{path}/Fonts");
        if let Ok(files) = std::fs::read_dir(folder) {
            for f in files.flatten() {
                let p = f.path();
                if p.extension().and_then(|p| p.to_str()) == Some("ttf") {
                    let url = NSURL::fileURLWithPath(&NSString::from_str(&p.to_string_lossy()));
                    unsafe {
                        CTFontManagerRegisterFontsForURL(
                            &*url as *const NSURL as *const AnyObject,
                            1,
                            std::ptr::null_mut(),
                        );
                    }
                }
            }
        }
    }
    // Use existing licensed Office fonts in place; do not copy them into the app.
    let mut loaded = std::collections::HashSet::new();
    for bundle in [
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint",
    ] {
        let app_url = NSWorkspace::sharedWorkspace()
            .URLForApplicationWithBundleIdentifier(&NSString::from_str(bundle));
        if let Some(url) = app_url {
            if let Some(path) = url.path() {
                let mut folders = vec![std::path::PathBuf::from(format!(
                    "{path}/Contents/Resources/sdx"
                ))];
                while let Some(folder) = folders.pop() {
                    if let Ok(entries) = std::fs::read_dir(folder) {
                        for entry in entries.flatten() {
                            let path = entry.path();
                            if path.is_dir() {
                                folders.push(path);
                                continue;
                            }
                            let name = entry.file_name().to_string_lossy().to_lowercase();
                            for face in ["regular", "semibold"] {
                                if !loaded.contains(face)
                                    && name.starts_with(&format!("segoeui-{face}_"))
                                    && name.ends_with(".woff")
                                {
                                    let url = NSURL::fileURLWithPath(&NSString::from_str(
                                        &path.to_string_lossy(),
                                    ));
                                    if unsafe {
                                        CTFontManagerRegisterFontsForURL(
                                            &*url as *const NSURL as *const AnyObject,
                                            1,
                                            std::ptr::null_mut(),
                                        )
                                    } {
                                        loaded.insert(face);
                                    }
                                }
                            }
                        }
                    }
                    if loaded.len() == 2 {
                        break;
                    }
                }
            }
        }
        if loaded.len() == 2 {
            break;
        }
    }
    let d = Delegate::alloc(mtm).set_ivars(DelegateIvars::default());
    let d: Retained<Delegate> = unsafe { msg_send![super(d), init] };
    app.setDelegate(Some(ProtocolObject::from_ref(&*d)));
    app.run();
}

struct AXIvars {
    action: Action,
}
define_class!(
 #[unsafe(super=NSAccessibilityElement)]#[thread_kind=MainThreadOnly]#[ivars=AXIvars]struct AXControl;
 unsafe impl NSObjectProtocol for AXControl{}
 impl AXControl{
  #[unsafe(method(accessibilityPerformPress))]fn press(&self)->bool{self.perform_press()}
 }
);
impl Canvas {
    fn ax_children(&self) -> Retained<NSArray<AnyObject>> {
        let s = self.ivars().state.borrow();
        let mut objects: Vec<Retained<AnyObject>> = vec![];
        if let Some(f) = self.ivars().search.get() {
            if !f.isHidden() {
                objects.push(unsafe { Retained::cast_unchecked(f.clone()) });
            }
        }
        if let Some(f) = self.ivars().input.get() {
            if !f.isHidden() {
                objects.push(unsafe { Retained::cast_unchecked(f.clone()) });
            }
        }
        let window = self.window();
        for h in &s.hits {
            if h.rect[1] + h.rect[3] < 0. || h.rect[1] > s.height || h.rect[2] <= 0. {
                continue;
            }
            if s.dialog.is_some()
                && !(matches!(h.action, Action::DialogOk | Action::DialogCancel)
                    || h.action == Action::Option("copy-properties".into()))
            {
                continue;
            }
            if !s.menus.is_empty()
                && !matches!(h.action,Action::Option(ref v) if v.starts_with("menu:"))
            {
                continue;
            }
            let node = AXControl::alloc(self.mtm()).set_ivars(AXIvars {
                action: h.action.clone(),
            });
            let node: Retained<AXControl> = unsafe { msg_send![super(node), init] };
            unsafe {
                let _: () = msg_send![&*node,setAccessibilityElement:true];
                let _: () = msg_send![&*node,setAccessibilityRole:ns_string!("AXButton")];
                let _: () = msg_send![&*node,setAccessibilityLabel:&*NSString::from_str(&h.label)];
                let _: () = msg_send![&*node,setAccessibilityEnabled:h.enabled];
                let _: () = msg_send![&*node,setAccessibilityParent:self];
            }
            if let Some(w) = &window {
                let frame = self.convertRect_toView(draw::nsrect(h.rect), None);
                let frame = w.convertRectToScreen(frame);
                unsafe {
                    let _: () = msg_send![&*node,setAccessibilityFrame:frame];
                }
            }
            objects.push(unsafe { Retained::cast_unchecked(node) });
        }
        let result = NSArray::from_retained_slice(&objects);
        *self.ivars().ax_nodes.borrow_mut() = objects;
        result
    }
}

impl AXControl {
    fn perform_press(&self) -> bool {
        let app = NSApplication::sharedApplication(self.mtm());
        if let Some(window) = app.mainWindow() {
            if let Some(view) = window.contentView() {
                if let Some(canvas) = view.downcast_ref::<Canvas>() {
                    canvas.dispatch(self.ivars().action.clone());
                    return true;
                }
            }
        }
        false
    }
}

fn process_details(p: &model::Process) -> String {
    let mut arguments = vec![0i8; 32768];
    let mut now: model::RawProcess = unsafe { std::mem::zeroed() };
    let same = unsafe { model::tm_read_process(p.raw.pid, &mut now) } != 0
        && now.start == p.raw.start
        && now.micro == p.raw.micro;
    let (args, files) = if same {
        let n = unsafe {
            model::tm_arguments(p.raw.pid, arguments.as_mut_ptr(), arguments.len() as i32)
        };
        let args = if n > 0 {
            model::cstr(&arguments)
        } else {
            "Unavailable".into()
        };
        (args, unsafe { model::tm_open_files(p.raw.pid) })
    } else {
        ("Process exited or identity changed".into(), -1)
    };
    let signature = if p.path.is_empty() {
        "Unavailable".into()
    } else {
        services::command(
            "/usr/bin/codesign",
            &["-dv", "--verbose=2", &p.path],
            Duration::from_secs(3),
        )
        .unwrap_or_else(|e| e)
    };
    format!("Name: {}\nPID: {}    Parent PID: {}\nOwner: {}    Status: {}\nBundle: {}\nArchitecture: {:#x}    Threads: {}    Nice: {}\nStarted: {} (Unix seconds)\nCPU: {:.1}%    Memory: {}\nExecutable: {}\nArguments: {}\nOpen files: {}\nSigning information:\n{}",p.title,p.raw.pid,p.raw.ppid,p.user,p.status(),p.bundle,p.raw.arch,p.raw.threads,p.raw.nice,p.raw.start,p.cpu,model::bytes(p.raw.memory as f64,false),p.path,args,if files>=0{files.to_string()}else{"Unavailable".into()},signature)
}
#[link(name = "ServiceManagement", kind = "framework")]
extern "C" {}
fn login_enabled() -> bool {
    unsafe {
        let cls = objc2::runtime::AnyClass::get(c"SMAppService").unwrap();
        let service: *mut AnyObject = msg_send![cls, mainAppService];
        let status: isize = msg_send![service, status];
        status == 1
    }
}
impl Canvas {
    fn change_login(&self) {
        unsafe {
            let cls = objc2::runtime::AnyClass::get(c"SMAppService").unwrap();
            let service: *mut AnyObject = msg_send![cls, mainAppService];
            let mut err: *mut AnyObject = std::ptr::null_mut();
            let ok: bool = if login_enabled() {
                msg_send![service,unregisterAndReturnError:&mut err]
            } else {
                msg_send![service,registerAndReturnError:&mut err]
            };
            if !ok {
                let message = if err.is_null() {
                    "Change login permission in System Settings → General → Login Items.".into()
                } else {
                    let description: Retained<NSString> = msg_send![err, localizedDescription];
                    description.to_string()
                };
                self.ivars().state.borrow_mut().dialog = Some(Dialog {
                    title: "Launch at login".into(),
                    message,
                    ok: "OK".into(),
                    action: Action::None,
                    input: false,
                });
            } else {
                self.ivars().state.borrow_mut().login_enabled = login_enabled();
            }
        }
        self.redraw();
    }
}

// Explicit opt-in export of this view only. It never captures another app or display.
struct WindowRecording {
    start: Instant,
    last: Instant,
    count: usize,
    writer: std::sync::mpsc::SyncSender<(u128, Vec<u8>)>,
}
impl Canvas {
    fn toggle_recording(&self) {
        if self.ivars().recording.borrow().is_some() {
            self.ivars().recording.borrow_mut().take();
            return;
        }
        let Ok(path) = std::fs::read_to_string(support().join("demo-export-path.txt")) else {
            return;
        };
        let folder = std::path::PathBuf::from(path.trim());
        if !folder.is_absolute() {
            return;
        }
        if std::fs::create_dir_all(&folder).is_err() {
            return;
        }
        let (tx, rx) = std::sync::mpsc::sync_channel::<(u128, Vec<u8>)>(8);
        std::thread::spawn(move || {
            for (ms, bytes) in rx {
                let _ = std::fs::write(folder.join(format!("{ms:010}.png")), bytes);
            }
        });
        let now = Instant::now();
        *self.ivars().recording.borrow_mut() = Some(WindowRecording {
            start: now,
            last: now - Duration::from_secs(1),
            count: 0,
            writer: tx,
        });
    }
    fn record_frame(&self) {
        let capture = {
            let mut slot = self.ivars().recording.borrow_mut();
            let Some(r) = slot.as_mut() else { return };
            if r.last.elapsed() < Duration::from_millis(95) {
                return;
            }
            if r.count >= 1800 {
                slot.take();
                return;
            }
            r.last = Instant::now();
            r.count += 1;
            (r.start.elapsed().as_millis(), r.writer.clone())
        };
        if let Some(bitmap) = self.bitmapImageRepForCachingDisplayInRect(self.bounds()) {
            self.cacheDisplayInRect_toBitmapImageRep(self.bounds(), &bitmap);
            if let Some(data) = unsafe {
                bitmap.representationUsingType_properties(
                    NSBitmapImageFileType::PNG,
                    &NSDictionary::new(),
                )
            } {
                let _ = capture.1.try_send((capture.0, data.to_vec()));
            }
        }
    }
}

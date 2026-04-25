use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{ComponentController, Controller, adw, gtk};

use tablepro_core::DriverRegistry;

use super::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};

pub struct App {
    registry: Arc<DriverRegistry>,
    window: adw::ApplicationWindow,
    dialog: Option<Controller<ConnectDialog>>,
    last_status: Option<String>,
}

#[derive(Debug)]
pub enum AppMsg {
    OpenConnect,
    Connected { table_count: usize, driver_id: String },
    DialogClosed,
}

#[relm4::component(pub)]
impl SimpleComponent for App {
    type Init = Arc<DriverRegistry>;
    type Input = AppMsg;
    type Output = ();

    view! {
        #[name = "window"]
        adw::ApplicationWindow {
            set_title: Some("TablePro Linux"),
            set_default_width: 1100,
            set_default_height: 720,

            adw::ToolbarView {
                add_top_bar = &adw::HeaderBar {
                    set_title_widget: Some(&adw::WindowTitle::new("TablePro Linux", "Phase 0")),

                    pack_start = &gtk::Button {
                        set_icon_name: "network-server-symbolic",
                        set_tooltip_text: Some("Connect"),
                        connect_clicked => AppMsg::OpenConnect,
                    },
                },

                #[wrap(Some)]
                set_content = &adw::StatusPage {
                    set_icon_name: Some("network-server-symbolic"),
                    set_title: "TablePro Linux",
                    #[watch]
                    set_description: Some(
                        model.last_status.as_deref()
                            .unwrap_or("Phase 0 scaffold. Click the server icon to connect.")
                    ),
                },
            },
        }
    }

    fn init(registry: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let model = App {
            registry,
            window: root.clone(),
            dialog: None,
            last_status: None,
        };
        let widgets = view_output!();
        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>) {
        match msg {
            AppMsg::OpenConnect => {
                let dialog = ConnectDialog::builder()
                    .launch(ConnectDialogInit {
                        registry: self.registry.clone(),
                    })
                    .forward(sender.input_sender(), |out| match out {
                        ConnectDialogOutput::Connected { table_count, driver_id } => {
                            AppMsg::Connected { table_count, driver_id }
                        }
                        ConnectDialogOutput::Closed => AppMsg::DialogClosed,
                    });
                dialog.widget().present(Some(&self.window));
                self.dialog = Some(dialog);
            }
            AppMsg::Connected { table_count, driver_id } => {
                self.last_status = Some(format!("Connected to {driver_id}: {table_count} table(s)."));
                self.dialog = None;
            }
            AppMsg::DialogClosed => {
                self.dialog = None;
            }
        }
    }
}

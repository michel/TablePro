use relm4::adw::prelude::*;
use relm4::factory::{DynamicIndex, FactoryComponent, FactorySender};
use relm4::{adw, gtk};

use tablepro_core::TableInfo;

#[derive(Debug)]
pub struct SidebarRow {
    pub info: TableInfo,
}

#[derive(Debug)]
pub enum SidebarRowMsg {
    Activated,
}

#[derive(Debug)]
pub enum SidebarRowOutput {
    Selected { schema: Option<String>, name: String },
}

#[relm4::factory(pub)]
impl FactoryComponent for SidebarRow {
    type Init = TableInfo;
    type Input = SidebarRowMsg;
    type Output = SidebarRowOutput;
    type CommandOutput = ();
    type ParentWidget = gtk::ListBox;

    view! {
        adw::ActionRow {
            set_title: &self.info.name,
            set_activatable: true,
            connect_activated => SidebarRowMsg::Activated,
        }
    }

    fn init_model(info: Self::Init, _index: &DynamicIndex, _sender: FactorySender<Self>) -> Self {
        Self { info }
    }

    fn update(&mut self, msg: Self::Input, sender: FactorySender<Self>) {
        match msg {
            SidebarRowMsg::Activated => {
                let _ = sender.output(SidebarRowOutput::Selected {
                    schema: self.info.schema.clone(),
                    name: self.info.name.clone(),
                });
            }
        }
    }
}

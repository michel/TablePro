use std::sync::OnceLock;

static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

pub fn handle() -> &'static tokio::runtime::Runtime {
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("tablepro-tokio")
            .build()
            .expect("tokio runtime")
    })
}

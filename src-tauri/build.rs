fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new().app_manifest(
            tauri_build::AppManifest::new().commands(&[
                "backend_status",
                "get_close_action",
                "set_close_action",
            ]),
        ),
    )
    .expect("failed to run tauri-build");
}
fn main() {
    if let Err(error) = cedar_poo_bridge::cli::run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

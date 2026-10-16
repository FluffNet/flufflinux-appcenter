//! HTTPS uses the system trust store, including administrator-provided roots,
//! as the previous native client did. Never disable certificate validation.
use std::time::Duration;
pub fn agent(timeout: Duration) -> ureq::Agent {
    ureq::Agent::config_builder()
        .tls_config(
            ureq::tls::TlsConfig::builder()
                .root_certs(ureq::tls::RootCerts::PlatformVerifier)
                .build(),
        )
        .timeout_global(Some(timeout))
        .max_redirects(0)
        .build()
        .into()
}

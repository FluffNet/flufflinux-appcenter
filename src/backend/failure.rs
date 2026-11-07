//! Conservative retry policy. Native error domains take precedence over text;
//! libflatpak/OSTree sometimes wrap a transport error in G_IO_ERROR_FAILED.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Failure {
    pub kind: &'static str,
    pub retryable: bool,
}
pub fn detail(message: &str) -> String {
    const LIMIT: usize = 8192;
    if message.len() <= LIMIT {
        return message.into();
    }
    let mut head = LIMIT / 2 - 4;
    while !message.is_char_boundary(head) {
        head -= 1;
    }
    let mut tail = message.len() - LIMIT / 2 + 4;
    while !message.is_char_boundary(tail) {
        tail += 1;
    }
    format!("{}\n...\n{}", &message[..head], &message[tail..])
}
impl Failure {
    pub fn replaces(self, previous: Option<Self>) -> bool {
        previous.is_none_or(|old| {
            self.kind == "cancelled"
                || (old.kind == "dependency" && self.kind != "dependency")
                || (old.retryable
                    && matches!(
                        self.kind,
                        "disk-space"
                            | "read-only"
                            | "authorization"
                            | "integrity"
                            | "flatpak-version"
                    ))
        })
    }
    fn new(kind: &'static str, retryable: bool) -> Self {
        Self { kind, retryable }
    }
    pub fn native(error: &glib::Error) -> Self {
        use gio::IOErrorEnum as Io;
        use libflatpak::Error as Flatpak;
        if error.matches(Io::Cancelled) {
            return Self::new("cancelled", false);
        }
        if error.matches(Flatpak::Skipped) || error.matches(Flatpak::Aborted) {
            return Self::new("dependency", false);
        }
        if error.matches(Io::NoSpace) || error.matches(Flatpak::OutOfSpace) {
            return Self::new("disk-space", false);
        }
        if error.matches(Io::ReadOnly) {
            return Self::new("read-only", false);
        }
        if [
            Flatpak::PermissionDenied,
            Flatpak::AuthenticationFailed,
            Flatpak::NotAuthorized,
            Flatpak::WrongUser,
        ]
        .iter()
        .any(|code| error.matches(*code))
            || error.matches(Io::PermissionDenied)
        {
            return Self::new("authorization", false);
        }
        if error.kind::<gio::TlsError>().is_some()
            || error.matches(Flatpak::Untrusted)
            || error.matches(Flatpak::InvalidData)
            || error.matches(Io::InvalidData)
        {
            return Self::new("integrity", false);
        }
        if error.matches(Flatpak::NeedNewFlatpak) {
            return Self::new("flatpak-version", false);
        }
        if [
            Flatpak::RemoteNotFound,
            Flatpak::RuntimeNotFound,
            Flatpak::RefNotFound,
            Flatpak::NotInstalled,
        ]
        .iter()
        .any(|code| error.matches(*code))
        {
            return Self::new("not-found", false);
        }
        if error.matches(Io::Busy) || error.matches(Io::WouldBlock) {
            return Self::new("busy", true);
        }
        if [
            Io::TimedOut,
            Io::HostNotFound,
            Io::HostUnreachable,
            Io::NetworkUnreachable,
            Io::ConnectionRefused,
            Io::NotConnected,
            Io::BrokenPipe,
            Io::PartialInput,
        ]
        .iter()
        .any(|code| error.matches(*code))
        {
            return Self::new("network", true);
        }
        if error.matches(gio::ResolverError::TemporaryFailure) {
            return Self::new("network", true);
        }
        Self::message(error.message())
    }
    pub fn message(message: &str) -> Self {
        let message = message.to_ascii_lowercase();
        for (needles, kind) in [
            (
                &[
                    "no space left",
                    "not enough free space",
                    "not enough disk space",
                ][..],
                "disk-space",
            ),
            (&["read-only file system"][..], "read-only"),
            (
                &[
                    "certificate",
                    "gpg",
                    "signature",
                    "checksum",
                    "hash mismatch",
                ][..],
                "integrity",
            ),
            (
                &[
                    "permission denied",
                    "not authorized",
                    "authentication failed",
                    "authorization failed",
                ][..],
                "authorization",
            ),
            (&["source changed", "source for "][..], "source-changed"),
        ] {
            if needles.iter().any(|needle| message.contains(needle)) {
                return Self::new(kind, false);
            }
        }
        // Stable libcurl codes and HTTP status tokens survive localization.
        if [
            "[6]",
            "[7]",
            "[18]",
            "[28]",
            "[52]",
            "[55]",
            "[56]",
            "http 408",
            "http 429",
            "http 500",
            "http 502",
            "http 503",
            "http 504",
            "status 408",
            "status 429",
            "status 500",
            "status 502",
            "status 503",
            "status 504",
            "connection reset",
            "connection timed out",
            "timeout was reached",
            "network is unreachable",
            "could not resolve host",
            "temporary failure in name resolution",
        ]
        .iter()
        .any(|needle| message.contains(needle))
        {
            return Self::new("network", true);
        }
        // A repository can change publication during a pull. Resolve once more
        // through the same source; never repair repositories or bypass signing.
        if ["http 404", "status 404"]
            .iter()
            .any(|needle| message.contains(needle))
        {
            return Self::new("publication", true);
        }
        Self::new("transaction", false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn skipped_dependents_do_not_erase_the_root_cause_or_its_retry_policy() {
        let network = Failure::native(&glib::Error::new(gio::IOErrorEnum::TimedOut, "first cause"));
        let skipped = Failure::native(&glib::Error::new(
            libflatpak::Error::Skipped,
            "skipped dependency",
        ));
        assert!(!skipped.replaces(Some(network)));
        assert!(network.replaces(Some(skipped)));
        let disk = Failure::native(&glib::Error::new(
            gio::IOErrorEnum::NoSpace,
            "later permanent failure",
        ));
        assert!(disk.replaces(Some(network)));
        assert!(!network.replaces(Some(disk)));
        assert!(
            Failure::native(&glib::Error::new(gio::IOErrorEnum::Cancelled, "cancelled"))
                .replaces(Some(network))
        );
    }
    #[test]
    fn retained_errors_are_bounded_and_keep_the_cause_at_both_ends() {
        let message = format!("start\n{}\nroot cause", "ש".repeat(100000));
        let bounded = detail(&message);
        assert!(bounded.len() <= 8192);
        assert!(bounded.starts_with("start") && bounded.ends_with("root cause"));
        assert_eq!(detail("short failure"), "short failure");
    }
    #[test]
    fn native_domains_win_even_when_the_message_sounds_retryable() {
        for (code, expected) in [
            (gio::IOErrorEnum::Cancelled, "cancelled"),
            (gio::IOErrorEnum::NoSpace, "disk-space"),
            (gio::IOErrorEnum::ReadOnly, "read-only"),
            (gio::IOErrorEnum::PermissionDenied, "authorization"),
            (gio::IOErrorEnum::InvalidData, "integrity"),
        ] {
            let failure = Failure::native(&glib::Error::new(code, "connection reset [28]"));
            assert_eq!(failure.kind, expected);
            assert!(!failure.retryable);
        }
        for code in [
            libflatpak::Error::OutOfSpace,
            libflatpak::Error::Untrusted,
            libflatpak::Error::NotAuthorized,
            libflatpak::Error::NeedNewFlatpak,
            libflatpak::Error::RemoteNotFound,
            libflatpak::Error::RuntimeNotFound,
        ] {
            assert!(!Failure::native(&glib::Error::new(code, "temporary failure")).retryable);
        }
    }
    #[test]
    fn transient_transport_and_locks_retry_but_unknown_errors_do_not() {
        for code in [
            gio::IOErrorEnum::TimedOut,
            gio::IOErrorEnum::BrokenPipe,
            gio::IOErrorEnum::NetworkUnreachable,
            gio::IOErrorEnum::Busy,
        ] {
            assert!(Failure::native(&glib::Error::new(code, "localized native message")).retryable);
        }
        for text in [
            "Server returned HTTP 503",
            "While pulling: [28] Timeout was reached",
            "Server returned status 404",
            "connection reset by peer",
        ] {
            assert!(Failure::message(text).retryable);
        }
        for text in [
            "certificate verification failed [28]",
            "checksum mismatch [56]",
            "permission denied [7]",
            "source changed",
            "unknown failure",
            "Server returned HTTP 403",
        ] {
            assert!(!Failure::message(text).retryable);
        }
    }
}

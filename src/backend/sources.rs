//! Flatpak source identity and trust policy. Names alone never establish trust.
use super::{flag, rows, storage, text};
use gio::prelude::*;
use glib::translate::*;
use libflatpak::{prelude::*, Installation, Remote};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, ffi::CString, path::PathBuf, ptr};

pub fn token(value: impl AsRef<[u8]>) -> String {
    format!("{:x}", Sha256::digest(value.as_ref()))
}
pub fn scope(installation: &Installation) -> String {
    if installation.is_user() {
        "user".into()
    } else {
        installation.id().unwrap_or_else(|| "default".into()).into()
    }
}
pub fn display_scope(installation: &Installation) -> String {
    match scope(installation).as_str() {
        "default" => "system".into(),
        value => value.into(),
    }
}
pub fn installation(scope: &str) -> Result<Installation, String> {
    match scope {
        "user" => Installation::new_user(gio::Cancellable::NONE),
        "system" | "default" => Installation::new_system(gio::Cancellable::NONE),
        id => Installation::new_system_with_id(Some(id), gio::Cancellable::NONE),
    }
    .map_err(|e| e.to_string())
}
pub fn installations() -> Result<Vec<Installation>, String> {
    let mut result = vec![installation("user")?];
    result.extend(
        libflatpak::system_installations(gio::Cancellable::NONE).map_err(|e| e.to_string())?,
    );
    Ok(result)
}
pub fn location(installation: &Installation) -> Result<PathBuf, String> {
    installation
        .path()
        .and_then(|p| p.path())
        .ok_or_else(|| "Flatpak installation has no local path".into())
}
pub fn url(remote: &Remote) -> String {
    remote.url().unwrap_or_default().into()
}
pub fn name(remote: &Remote) -> String {
    remote.name().unwrap_or_default().into()
}
pub fn identity(installation: &Installation, remote: &Remote) -> String {
    format!("{}:{}:{}", scope(installation), name(remote), url(remote))
}
pub fn official_definition(value: &str) -> Option<&'static str> {
    let u = url::Url::parse(value).ok()?;
    // Url normalizes an explicit default port, so reject it in the authority too.
    let authority = value.strip_prefix("https://")?.split('/').next()?;
    if !u.username().is_empty()
        || u.password().is_some()
        || authority.contains(':')
        || u.query().is_some()
        || u.fragment().is_some()
        || !matches!(u.host_str(), Some("dl.flathub.org" | "flathub.org"))
    {
        return None;
    }
    match u.path().strip_suffix('/').unwrap_or(u.path()) {
        "/repo" => Some("https://dl.flathub.org/repo/flathub.flatpakrepo"),
        "/beta-repo" => Some("https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo"),
        _ => None,
    }
}
pub fn valid_name(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 255
        && value.bytes().enumerate().all(|(i, c)| {
            c.is_ascii_alphanumeric() || c == b'_' || (i > 0 && (c == b'-' || c == b'.'))
        })
}
pub fn user_name(user: &Installation, system: &Installation, remote: &Remote) -> String {
    let name = name(remote);
    match user.remote_by_name(&name, gio::Cancellable::NONE) {
        Ok(existing) if url(&existing) != url(remote) => {
            format!("{name}-system-{}", &token(identity(system, remote))[..10])
        }
        _ => name,
    }
}
pub fn removed_sources() -> BTreeSet<String> {
    // QSettings uses comma-separated string lists. Existing configuration stays readable.
    storage::config()
        .string("Sources", "removedSystemSources")
        .unwrap_or_default()
        .split([',', ';'])
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
        .collect()
}
pub fn suppressed(system: &Installation, remote: &Remote) -> bool {
    removed_sources().contains(&token(identity(system, remote)))
}

// libflatpak-rs does not expose OSTree source-key inspection. This small RAII
// boundary calls the native C library directly; all source policy stays in Rust.
#[repr(C)]
struct OstreeRepo {
    _opaque: [u8; 0],
}
#[link(name = "ostree-1")]
unsafe extern "C" {
    fn ostree_repo_new(path: *mut gio::ffi::GFile) -> *mut OstreeRepo;
    fn ostree_repo_open(
        repo: *mut OstreeRepo,
        cancel: *mut gio::ffi::GCancellable,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    fn ostree_repo_copy_config(repo: *mut OstreeRepo) -> *mut glib::ffi::GKeyFile;
    fn ostree_repo_remote_get_gpg_keys(
        repo: *mut OstreeRepo,
        remote: *const libc::c_char,
        ids: *const *const libc::c_char,
        keys: *mut *mut glib::ffi::GPtrArray,
        cancel: *mut gio::ffi::GCancellable,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    fn ostree_repo_remote_add(
        repo: *mut OstreeRepo,
        name: *const libc::c_char,
        url: *const libc::c_char,
        options: *mut glib::ffi::GVariant,
        cancel: *mut gio::ffi::GCancellable,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    fn ostree_repo_remote_gpg_import(
        repo: *mut OstreeRepo,
        name: *const libc::c_char,
        stream: *mut gio::ffi::GInputStream,
        ids: *const *const libc::c_char,
        imported: *mut u32,
        cancel: *mut gio::ffi::GCancellable,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    fn ostree_repo_remote_delete(
        repo: *mut OstreeRepo,
        name: *const libc::c_char,
        cancel: *mut gio::ffi::GCancellable,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
}
struct Repo(*mut OstreeRepo);
impl Drop for Repo {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                glib::gobject_ffi::g_object_unref(self.0.cast());
            }
        }
    }
}
fn native_result(ok: i32, error: *mut glib::ffi::GError) -> Result<(), String> {
    if !error.is_null() {
        return Err(unsafe { from_glib_full::<_, glib::Error>(error) }.to_string());
    }
    if ok == 0 {
        Err("The source repository could not be read".into())
    } else {
        Ok(())
    }
}
impl Repo {
    fn open(
        installation: &Installation,
        cancel: Option<&gio::Cancellable>,
    ) -> Result<Self, String> {
        let path = gio::File::for_path(location(installation)?.join("repo"));
        let repo = Self(unsafe { ostree_repo_new(path.to_glib_none().0) });
        if repo.0.is_null() {
            return Err("Could not open source repository".into());
        }
        let mut error = ptr::null_mut();
        native_result(
            unsafe { ostree_repo_open(repo.0, cancel.to_glib_none().0, &mut error) },
            error,
        )?;
        Ok(repo)
    }
    fn config(&self) -> glib::KeyFile {
        unsafe { from_glib_full(ostree_repo_copy_config(self.0)) }
    }
    fn signing_keys(&self, name: &str) -> Result<Vec<String>, String> {
        let name = CString::new(name).map_err(|e| e.to_string())?;
        let mut keys = ptr::null_mut();
        let mut error = ptr::null_mut();
        native_result(
            unsafe {
                ostree_repo_remote_get_gpg_keys(
                    self.0,
                    name.as_ptr(),
                    ptr::null(),
                    &mut keys,
                    ptr::null_mut(),
                    &mut error,
                )
            },
            error,
        )?;
        if keys.is_null() {
            return Ok(Vec::new());
        }
        let mut result = Vec::new();
        // The array owns its variants. Borrow each only until the array is freed.
        unsafe {
            for i in 0..(*keys).len {
                let v: glib::Variant = from_glib_none(
                    (*keys)
                        .pdata
                        .add(i as usize)
                        .read()
                        .cast::<glib::ffi::GVariant>(),
                );
                result.push(v.print(true).into());
            }
            glib::ffi::g_ptr_array_unref(keys);
        }
        result.sort();
        Ok(result)
    }
}
pub fn source_key(installation: &Installation, remote: &Remote) -> Result<String, String> {
    let repo = Repo::open(installation, None)?;
    let config = repo.config();
    let group = format!("remote \"{}\"", name(remote));
    let mut options = json!({});
    for key in config.keys(&group).map_err(|e| e.to_string())? {
        if [
            "xa.title",
            "xa.comment",
            "xa.description",
            "xa.homepage",
            "xa.icon",
            "xa.disable",
            "xa.prio",
            "xa.fluff-system-source",
            "gpgkeypath",
        ]
        .contains(&key.as_str())
        {
            continue;
        }
        options[key.as_str()] = config
            .string(&group, &key)
            .map_err(|e| e.to_string())?
            .as_str()
            .into();
    }
    options["signing-keys"] = json!(repo.signing_keys(&name(remote))?);
    let filter = text(&options, "xa.filter");
    if !filter.is_empty() {
        options["xa.filter"] = token(std::fs::read(filter).map_err(|e| e.to_string())?).into();
    }
    Ok(storage::checksum(&options))
}
pub fn list() -> Vec<Value> {
    let mut result = Vec::new();
    for installation in installations().unwrap_or_default() {
        for remote in installation
            .list_remotes(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            if remote.remote_type() != libflatpak::RemoteType::Static {
                continue;
            }
            result.push(json!({"name":name(&remote),"title":remote.title().unwrap_or_default().as_str(),
                "url":url(&remote),"scope":scope(&installation),"enabled":!remote.is_disabled(),
                "sourceKey":source_key(&installation,&remote).unwrap_or_default(),"verified":remote.is_gpg_verify()}));
        }
    }
    result
}
pub fn group(sources: &[Value]) -> Vec<Value> {
    let mut result: Vec<Value> = Vec::new();
    for source in sources {
        let index = result.iter().position(|candidate| {
            !text(source, "sourceKey").is_empty()
                && candidate["sourceKey"] == source["sourceKey"]
                && !rows(&candidate["members"])
                    .iter()
                    .any(|m| m["scope"] == source["scope"])
        });
        let mut row = index
            .map(|i| result[i].clone())
            .unwrap_or_else(|| source.clone());
        let mut members = rows(&row["members"]).to_vec();
        members.push(source.clone());
        let user = text(source, "scope") == "user";
        row["hasUser"] = (flag(&row, "hasUser") || user).into();
        row["hasSystem"] = (flag(&row, "hasSystem") || !user).into();
        if flag(&row, "hasUser") && flag(&row, "hasSystem") {
            row["scope"] = "merged".into();
        }
        if user {
            row["enabled"] = source["enabled"].clone();
        }
        let mut ids: Vec<_> = members
            .iter()
            .map(|m| {
                format!(
                    "{}:{}:{}:{}",
                    text(m, "scope"),
                    text(m, "name"),
                    text(m, "url"),
                    text(m, "sourceKey")
                )
            })
            .collect();
        ids.sort();
        row["id"] = token(ids.join("\n")).into();
        row["members"] = members.into();
        if let Some(i) = index {
            result[i] = row;
        } else {
            result.push(row);
        }
    }
    result
}
pub fn mirror(
    user: &Installation,
    system: &Installation,
    remote: &Remote,
    cancel: &gio::Cancellable,
) -> Result<(), String> {
    let name = user_name(user, system, remote);
    if let Ok(existing) = user.remote_by_name(&name, Some(cancel)) {
        return if url(&existing) == url(remote) {
            Ok(())
        } else {
            Err(format!(
                "The user source {name} has a different address. It has not been changed."
            ))
        };
    }
    let source = Repo::open(system, Some(cancel))?;
    let target = Repo::open(user, Some(cancel))?;
    let config = source.config();
    let group = format!("remote \"{}\"", self::name(remote));
    let options = glib::VariantDict::new(None);
    for key in config.keys(&group).map_err(|e| e.to_string())? {
        if key != "xa.disable" {
            options.insert(
                &key,
                config
                    .string(&group, &key)
                    .map_err(|e| e.to_string())?
                    .as_str(),
            );
        }
    }
    options.insert("xa.disable", true);
    options.insert("xa.fluff-system-source", token(identity(system, remote)));
    let options = options.end();
    let signing_keys = std::fs::read(
        location(system)?
            .join("repo")
            .join(format!("{}.trustedkeys.gpg", self::name(remote))),
    )
    .unwrap_or_default();
    let key_path = config.string(&group, "gpgkeypath").unwrap_or_default();
    if (remote.is_gpg_verify()
        || config
            .boolean(&group, "gpg-verify-summary")
            .unwrap_or(false))
        && signing_keys.is_empty()
        && key_path.is_empty()
    {
        return Err(format!(
            "Cannot copy the signing keys for {name}. Verification has not been disabled."
        ));
    }
    let native_name = CString::new(name.as_str()).map_err(|e| e.to_string())?;
    let native_url = CString::new(url(remote)).map_err(|e| e.to_string())?;
    let mut error = ptr::null_mut();
    native_result(
        unsafe {
            ostree_repo_remote_add(
                target.0,
                native_name.as_ptr(),
                native_url.as_ptr(),
                options.to_glib_none().0,
                cancel.to_glib_none().0,
                &mut error,
            )
        },
        error,
    )?;
    if !signing_keys.is_empty() {
        let stream = gio::MemoryInputStream::from_bytes(&glib::Bytes::from_owned(signing_keys));
        let stream: &gio::InputStream = stream.upcast_ref();
        let mut error = ptr::null_mut();
        if let Err(problem) = native_result(
            unsafe {
                ostree_repo_remote_gpg_import(
                    target.0,
                    native_name.as_ptr(),
                    stream.to_glib_none().0,
                    ptr::null(),
                    ptr::null_mut(),
                    cancel.to_glib_none().0,
                    &mut error,
                )
            },
            error,
        ) {
            unsafe {
                ostree_repo_remote_delete(
                    target.0,
                    native_name.as_ptr(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                );
            }
            let _ = user.drop_caches(gio::Cancellable::NONE);
            return Err(problem);
        }
    }
    user.drop_caches(Some(cancel)).map_err(|e| e.to_string())?;
    let copy = user
        .remote_by_name(&name, Some(cancel))
        .map_err(|e| e.to_string())?;
    copy.set_disabled(remote.is_disabled());
    user.modify_remote(&copy, Some(cancel))
        .map_err(|e| e.to_string())
}
pub fn remember_removal(user: &Installation, remote: &Remote) -> Result<(), String> {
    let mut removed = removed_sources();
    for system in
        libflatpak::system_installations(gio::Cancellable::NONE).map_err(|e| e.to_string())?
    {
        for source in system
            .list_remotes(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            if user_name(user, &system, &source) == name(remote) && url(&source) == url(remote) {
                removed.insert(token(identity(&system, &source)));
            }
        }
    }
    storage::update_config(|config| {
        config.set_string(
            "Sources",
            "removedSystemSources",
            &removed.into_iter().collect::<Vec<_>>().join(", "),
        );
        config.set_boolean("Sources", "initialized", true);
    })
    .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn official_sources_require_the_exact_trusted_endpoint() {
        assert!(official_definition("https://dl.flathub.org/repo/").is_some());
        for url in [
            "http://dl.flathub.org/repo",
            "https://user@dl.flathub.org/repo",
            "https://dl.flathub.org:443/repo",
            "https://dl.flathub.org/repo?x=1",
            "https://flathub.org.evil/repo",
            "https://dl.flathub.org/other",
        ] {
            assert!(official_definition(url).is_none(), "{url}");
        }
    }
    #[test]
    fn distinct_keys_and_same_scope_never_merge() {
        let user = json!({"scope":"user","name":"a","url":"https://test","sourceKey":"key","enabled":false});
        let system = json!({"scope":"system","name":"b","url":"https://test","sourceKey":"key","enabled":true});
        let merged = group(&[system.clone(), user.clone()]);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0]["enabled"], false);
        let mut different = system;
        different["sourceKey"] = "different".into();
        assert_eq!(group(&[user.clone(), different]).len(), 2);
        assert_eq!(group(&[user.clone(), user]).len(), 2);
    }
}

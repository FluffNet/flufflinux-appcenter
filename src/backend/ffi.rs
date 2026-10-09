//! The bridge has one opaque Rust state owner and JSON messages. Returned
//! strings are owned by Rust until the bridge calls fluff_backend_string_free.
use super::manager::Manager;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, CStr, CString},
    panic::{catch_unwind, AssertUnwindSafe},
};
fn output(value: Value) -> *mut c_char {
    CString::new(value.to_string())
        .expect("JSON has no literal NUL")
        .into_raw()
}
unsafe fn input(pointer: *const c_char) -> Value {
    if pointer.is_null() {
        return Value::Null;
    }
    // The Qt adapter supplies a live, NUL-terminated UTF-8 buffer for this call.
    let bytes = unsafe { CStr::from_ptr(pointer) }.to_bytes();
    if bytes.len() > 128 * 1024 * 1024 {
        return Value::Null;
    }
    serde_json::from_slice(bytes).unwrap_or(Value::Null)
}
#[no_mangle]
/// # Safety
/// `catalog` is null or a live NUL-terminated string for the duration of the call.
pub unsafe extern "C" fn fluff_backend_new(catalog: *const c_char) -> *mut Manager {
    catch_unwind(|| {
        let apps = match unsafe { input(catalog) } {
            Value::Array(apps) => apps,
            _ => vec![],
        };
        Box::into_raw(Box::new(Manager::new(apps)))
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
/// # Safety
/// `manager` is null or a live, exclusively borrowed result of `fluff_backend_new`.
pub unsafe extern "C" fn fluff_backend_initial(manager: *mut Manager) -> *mut c_char {
    if manager.is_null() {
        return output(json!({}));
    }
    output(unsafe { &mut *manager }.initial())
}
#[no_mangle]
/// # Safety
/// `manager` is exclusively borrowed and live; `request` is null or a live
/// NUL-terminated string. Calls for the same manager must not overlap.
pub unsafe extern "C" fn fluff_backend_dispatch(
    manager: *mut Manager,
    request: *const c_char,
) -> *mut c_char {
    if manager.is_null() {
        return output(json!({}));
    }
    let request = unsafe { input(request) };
    let result = catch_unwind(AssertUnwindSafe(|| {
        unsafe { &mut *manager }.dispatch(super::text(&request, "action"), &request["args"])
    }));
    match result {
        Ok(value) => output(value),
        Err(_) => {
            // Never unwind into C++ or continue an inconsistent transaction state.
            eprintln!("The Rust backend encountered an internal state error.");
            std::process::abort()
        }
    }
}
#[no_mangle]
/// # Safety
/// `manager` is null or an unfreed result of `fluff_backend_new`, without borrowers.
pub unsafe extern "C" fn fluff_backend_drop(manager: *mut Manager) {
    if !manager.is_null() {
        drop(unsafe { Box::from_raw(manager) });
    }
}
#[no_mangle]
/// # Safety
/// `value` is null or an unfreed string returned by this module, never modified.
pub unsafe extern "C" fn fluff_backend_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[no_mangle]
/// # Safety
/// `request` is null or a live NUL-terminated string for the duration of this call.
pub unsafe extern "C" fn fluff_backend_utility(request: *const c_char) -> *mut c_char {
    let request = unsafe { input(request) };
    output(match super::text(&request, "operation") {
        "network" => {
            json!({"state":super::network_state(super::number(&request,"State") as u32,super::number(&request,"Connectivity") as u32)})
        }
        _ => super::preferences::call(&request),
    })
}

// Not present in normal builds. Native tests use real Rust persistence rather
// than retaining the replaced C++ implementation as a second source of truth.
#[cfg(feature = "native-tests")]
#[no_mangle]
/// # Safety
/// `request` is null or a live NUL-terminated fixture JSON string.
pub unsafe extern "C" fn fluff_backend_fixture(request: *const c_char) -> *mut c_char {
    use super::{catalog, storage, text};
    use chrono::{DateTime, Utc};
    use std::path::Path;
    let request = unsafe { input(request) };
    let path = Path::new(text(&request, "path"));
    let date = DateTime::parse_from_rfc3339(text(&request, "date"))
        .map(|d| d.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now());
    output(match text(&request, "operation") {
        "fingerprint" => json!({"value":catalog::fingerprint().unwrap_or_default()}),
        "snapshot" => {
            catalog::snapshot(&request["request"], super::rows(&request["apps"]).to_vec())
        }
        "write" => {
            json!({"ok":storage::write_cache(path,text(&request,"fingerprint"),super::rows(&request["apps"]),date).is_ok()})
        }
        "read" => match storage::read_cache(path, text(&request, "fingerprint"), date) {
            Some(cache) => {
                json!({"valid":true,"apps":cache.apps,"savedAt":cache.saved_at.to_rfc3339()})
            }
            None => json!({"valid":false}),
        },
        "fresh" => json!({"value":storage::fresh(date,Utc::now())}),
        "stages" => {
            super::progress::stages(super::rows(&request["operations"]), text(&request, "phase"))
        }
        "format" => {
            json!({"size":super::bytes(super::number(&request,"bytes")),"speed":super::progress::DownloadRate::display(super::number(&request,"speed") as f64),"date":super::locale::date(text(&request,"date"))})
        }
        _ => Value::Null,
    })
}

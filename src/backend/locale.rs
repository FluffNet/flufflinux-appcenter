//! Delegate text presentation to the same native locale as QML, not storage.
use std::ffi::{c_char, CStr, CString};
extern "C" {
    fn fluff_ui_number(value: f64) -> *mut c_char;
    fn fluff_ui_date(value: *const c_char) -> *mut c_char;
}
unsafe fn owned(value: *mut c_char) -> String {
    if value.is_null() {
        return String::new();
    }
    let result = unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .into_owned();
    unsafe { libc::free(value.cast()) };
    result
}
pub fn decimal(value: f64) -> String {
    unsafe { owned(fluff_ui_number(value)) }
}
pub fn date(value: &str) -> String {
    let Ok(value) = CString::new(value) else {
        return String::new();
    };
    unsafe { owned(fluff_ui_date(value.as_ptr())) }
}

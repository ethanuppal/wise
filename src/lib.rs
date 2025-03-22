// Copyright (C) 2024 Ethan Uppal.
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3 of the License only.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

use std::{error::Error, ptr};

use accessibility_sys::{
    AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt,
};
use cocoa::{
    appkit::NSRunningApplication,
    base::{id, nil},
    foundation::{NSArray, NSString},
};
use core_foundation_sys::{
    base::{CFTypeRef, kCFAllocatorDefault},
    dictionary::CFDictionaryCreate,
    number::kCFBooleanTrue,
};
use memory::{ManageWithRc, Rc};
use snafu::Snafu;

pub mod memory;

#[derive(Debug, Snafu)]
pub enum WiseError {
    #[snafu(display("Failed to create or copy CoreFoundation object"))]
    CouldNotCreateCFObject,
    #[snafu(display("Apple API object was unexpectedly null"))]
    UnexpectedNull,
    #[snafu(whatever, display("{message}"))]
    Whatever {
        message: String,
        #[snafu(source(from(Box<dyn Error>, Some)))]
        source: Option<Box<dyn Error>>,
    },
}

pub fn has_accessibility_permissions() -> Result<bool, WiseError> {
    // SAFETY: `kAXTrustedCheckOptionPrompt` should be initialized by
    // CoreFoundation.
    let keys = [unsafe { kAXTrustedCheckOptionPrompt } as CFTypeRef];

    // SAFETY: `kCFBooleanTrue` should be initialized by CoreFoundation.
    let values = [unsafe { kCFBooleanTrue } as CFTypeRef];

    // SAFETY:
    // - `keys.as_ptr()` is a valid pointer to a C array of at least 1
    //   pointer-sized value.
    // - `values.as_ptr()` is likewise.
    let options = unsafe {
        Rc::new_const(CFDictionaryCreate(
            kCFAllocatorDefault,
            keys.as_ptr(),
            values.as_ptr(),
            1,
            ptr::null(),
            ptr::null(),
        ))
        .ok_or(WiseError::CouldNotCreateCFObject)
    }?;

    // SAFETY: `options` is a valid dictionary of options.
    let is_trusted = unsafe { AXIsProcessTrustedWithOptions(options.get()) };

    Ok(is_trusted)
}

pub fn running_apps_with_bundle_id(
    bundle_id: &str,
) -> Result<Box<[Rc<id>]>, WiseError> {
    let mut running_apps;

    let bundle_id_nsstring =
    // SAFETY: &str to NSString.
        unsafe { NSString::alloc(nil).init_str(bundle_id).into_rc() }
            .ok_or(WiseError::CouldNotCreateCFObject)?;

    // SAFETY: `bundle_id_nsstring` is nonnull.
    let apps_nsarray = unsafe {
        NSRunningApplication::runningApplicationsWithBundleIdentifier(
            nil,
            bundle_id_nsstring.get(),
        )
        .into_rc()
    }
    .ok_or(WiseError::UnexpectedNull)?;

    // SAFETY: `runningApplicationsWithBundleIdentifier` returns an `NSArray`.
    let count = unsafe { NSArray::count(apps_nsarray.get()) } as usize;

    running_apps = Vec::with_capacity(count);
    for i in 0..count {
        // SAFETY: `runningApplicationsWithBundleIdentifier` returns an
        // `NSArray`. Each element is managed by the `NSArray`, so we use
        // `as_rc`.
        let running_app = unsafe {
            NSArray::objectAtIndex(apps_nsarray.get(), i as u64).as_rc()
        }
        .ok_or(WiseError::UnexpectedNull)?;
        running_apps.push(running_app);
    }

    Ok(running_apps.into_boxed_slice())
}

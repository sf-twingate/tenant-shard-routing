#![cfg_attr(not(feature = "std"), no_std)]

extern crate alloc;

pub mod config;
pub mod tenant;
pub mod cache;

#[cfg(test)]
mod tests;
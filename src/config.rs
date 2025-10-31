// FILE: src/config.rs
use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub agg_window_sec: u64,
    pub output_dir: String,
    pub seal_endpoint: Option<String>,
    pub max_records_per_window: usize,
    pub outlier_threshold_multiplier: f64,
    pub enable_signature_verification: bool,
}

impl Config {
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Config {
            host: env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()?,
            agg_window_sec: env::var("AGG_WINDOW_SEC")
                .unwrap_or_else(|_| "3600".to_string())
                .parse()?,
            output_dir: env::var("OUTPUT_DIR")
                .unwrap_or_else(|_| "./out".to_string()),
            seal_endpoint: env::var("SEAL_ENDPOINT").ok(),
            max_records_per_window: env::var("MAX_RECORDS_PER_WINDOW")
                .unwrap_or_else(|_| "1000".to_string())
                .parse()?,
            outlier_threshold_multiplier: env::var("OUTLIER_THRESHOLD_MULTIPLIER")
                .unwrap_or_else(|_| "3.0".to_string())
                .parse()?,
            enable_signature_verification: env::var("ENABLE_SIGNATURE_VERIFICATION")
                .unwrap_or_else(|_| "true".to_string())
                .parse()?,
        })
    }
}
// FILE: src/models.rs
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeterRecord {
    pub meter_id: String,
    pub timestamp: i64,
    pub kwh_delta: f64,
    pub nonce: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedMeterData {
    pub record: MeterRecord,
    pub sig: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifiedRecord {
    pub record: MeterRecord,
    pub signature: String,
    pub verification_timestamp: DateTime<Utc>,
    pub record_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregationWindow {
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    pub records: Vec<VerifiedRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofData {
    pub proof_id: Uuid,
    pub aggregate_kwh: f64,
    pub merkle_root: String,
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    pub record_count: usize,
    pub meter_ids: Vec<String>,
    pub generated_at: DateTime<Utc>,
    pub version: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IngestResponse {
    pub success: bool,
    pub message: String,
    pub timestamp: DateTime<Utc>,
    pub receipt_id: Uuid,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub timestamp: DateTime<Utc>,
    pub uptime_seconds: u64,
    pub version: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusResponse {
    pub status: String,
    pub current_window: Option<WindowStatus>,
    pub total_records_processed: usize,
    pub total_proofs_generated: usize,
    pub last_proof_generated: Option<DateTime<Utc>>,
    pub configuration: StatusConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WindowStatus {
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    pub records_collected: usize,
    pub time_remaining_seconds: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusConfig {
    pub agg_window_sec: u64,
    pub max_records_per_window: usize,
    pub enable_signature_verification: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SealRequest {
    pub proof_id: Option<Uuid>,
    pub force_latest: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SealResponse {
    pub success: bool,
    pub message: String,
    pub proof_id: Option<Uuid>,
    pub seal_endpoint: Option<String>,
    pub seal_response: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
    pub timestamp: DateTime<Utc>,
    pub details: Option<serde_json::Value>,
}
// FILE: src/handlers.rs
use actix_web::{web, HttpResponse, Result};
use chrono::Utc;
use log::{info, warn, error};
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::config::Config;
use crate::models::*;
use crate::aggregator::DataAggregator;
use crate::seal::SealService;

/// Health check endpoint
pub async fn health_check() -> Result<HttpResponse> {
    let response = HealthResponse {
        status: "healthy".to_string(),
        timestamp: Utc::now(),
        uptime_seconds: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
        version: "1.0.0".to_string(),
    };
    
    Ok(HttpResponse::Ok().json(response))
}

/// Get enclave status and statistics
pub async fn get_status(
    aggregator: web::Data<Arc<Mutex<DataAggregator>>>,
    config: web::Data<Config>,
) -> Result<HttpResponse> {
    let aggregator = aggregator.lock().await;
    let stats = aggregator.get_stats();
    let window_status = aggregator.get_window_status();
    
    let response = StatusResponse {
        status: "running".to_string(),
        current_window: window_status,
        total_records_processed: stats.total_records_processed,
        total_proofs_generated: stats.total_proofs_generated,
        last_proof_generated: stats.last_proof_generated,
        configuration: StatusConfig {
            agg_window_sec: config.agg_window_sec,
            max_records_per_window: config.max_records_per_window,
            enable_signature_verification: config.enable_signature_verification,
        },
    };
    
    Ok(HttpResponse::Ok().json(response))
}

/// Ingest signed meter data
pub async fn ingest_data(
    payload: web::Json<SignedMeterData>,
    aggregator: web::Data<Arc<Mutex<DataAggregator>>>,
) -> Result<HttpResponse> {
    let data = payload.into_inner();
    
    info!("Received meter data: meter_id={}, kwh_delta={}, timestamp={}", 
          data.record.meter_id, data.record.kwh_delta, data.record.timestamp);

    // Validate payload
    if let Err(validation_error) = validate_meter_record(&data.record) {
        warn!("Invalid meter record: {}", validation_error);
        return Ok(HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid meter record".to_string(),
            code: "VALIDATION_ERROR".to_string(),
            timestamp: Utc::now(),
            details: Some(serde_json::json!({ "message": validation_error })),
        }));
    }

    // Process the record
    let mut aggregator = aggregator.lock().await;
    match aggregator.process_record(data.record, data.sig).await {
        Ok(receipt_id) => {
            let response = IngestResponse {
                success: true,
                message: "Data ingested successfully".to_string(),
                timestamp: Utc::now(),
                receipt_id,
            };
            Ok(HttpResponse::Ok().json(response))
        }
        Err(e) => {
            error!("Failed to process meter record: {}", e);
            
            // Determine appropriate error code and status
            let (status_code, error_code) = if e.to_string().contains("Invalid signature") {
                (HttpResponse::Unauthorized(), "INVALID_SIGNATURE")
            } else if e.to_string().contains("Duplicate record") {
                (HttpResponse::Conflict(), "DUPLICATE_RECORD")
            } else {
                (HttpResponse::InternalServerError(), "PROCESSING_ERROR")
            };
            
            Ok(status_code.json(ErrorResponse {
                error: "Failed to process meter data".to_string(),
                code: error_code.to_string(),
                timestamp: Utc::now(),
                details: Some(serde_json::json!({ "message": e.to_string() })),
            }))
        }
    }
}

/// Get latest generated proof
pub async fn get_latest_proof(
    aggregator: web::Data<Arc<Mutex<DataAggregator>>>,
) -> Result<HttpResponse> {
    let aggregator = aggregator.lock().await;
    
    match aggregator.get_latest_proof().await {
        Ok(Some(proof)) => {
            info!("Retrieved latest proof: {}", proof.proof_id);
            Ok(HttpResponse::Ok().json(proof))
        }
        Ok(None) => {
            info!("No proofs available");
            Ok(HttpResponse::NotFound().json(ErrorResponse {
                error: "No proofs available".to_string(),
                code: "NO_PROOFS".to_string(),
                timestamp: Utc::now(),
                details: None,
            }))
        }
        Err(e) => {
            error!("Failed to retrieve latest proof: {}", e);
            Ok(HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to retrieve proof".to_string(),
                code: "RETRIEVAL_ERROR".to_string(),
                timestamp: Utc::now(),
                details: Some(serde_json::json!({ "message": e.to_string() })),
            }))
        }
    }
}

/// Seal proof to Walrus/Seal endpoint
pub async fn seal_proof(
    payload: web::Json<SealRequest>,
    aggregator: web::Data<Arc<Mutex<DataAggregator>>>,
    config: web::Data<Config>,
) -> Result<HttpResponse> {
    let request = payload.into_inner();
    let seal_service = SealService::new(config.seal_endpoint.clone());
    
    // Get proof to seal
    let proof = if let Some(proof_id) = request.proof_id {
        // Get proof by ID from aggregator
        let aggregator = aggregator.lock().await;
        aggregator.get_proof_by_id(&proof_id).await.map_err(|e| {
            error!("Failed to retrieve proof by ID {}: {}", proof_id, e);
            e
        })?
        info!("Sealing specific proof: {}", proof_id);
        return Ok(HttpResponse::NotImplemented().json(ErrorResponse {
            error: "Sealing specific proof by ID not yet implemented".to_string(),
            code: "NOT_IMPLEMENTED".to_string(),
            timestamp: Utc::now(),
            details: None,
        }));
    } else if request.force_latest {
        // Get latest proof
        let aggregator = aggregator.lock().await;
        match aggregator.get_latest_proof().await {
            Ok(Some(proof)) => proof,
            Ok(None) => {
                return Ok(HttpResponse::NotFound().json(ErrorResponse {
                    error: "No proofs available to seal".to_string(),
                    code: "NO_PROOFS".to_string(),
                    timestamp: Utc::now(),
                    details: None,
                }));
            }
            Err(e) => {
                error!("Failed to retrieve proof for sealing: {}", e);
                return Ok(HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Failed to retrieve proof".to_string(),
                    code: "RETRIEVAL_ERROR".to_string(),
                    timestamp: Utc::now(),
                    details: Some(serde_json::json!({ "message": e.to_string() })),
                }));
            }
        }
    } else {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse {
            error: "Must specify proof_id or set force_latest=true".to_string(),
            code: "INVALID_REQUEST".to_string(),
            timestamp: Utc::now(),
            details: None,
        }));
    };

    // Seal the proof
    info!("Sealing proof {} to Walrus/Seal endpoint", proof.proof_id);
    match seal_service.seal_proof(&proof).await {
        Ok(seal_response) => {
            info!("Successfully sealed proof {}", proof.proof_id);
            Ok(HttpResponse::Ok().json(SealResponse {
                success: true,
                message: "Proof sealed successfully".to_string(),
                proof_id: Some(proof.proof_id),
                seal_endpoint: config.seal_endpoint.clone(),
                seal_response: Some(seal_response),
            }))
        }
        Err(e) => {
            error!("Failed to seal proof {}: {}", proof.proof_id, e);
            Ok(HttpResponse::InternalServerError().json(SealResponse {
                success: false,
                message: format!("Failed to seal proof: {}", e),
                proof_id: Some(proof.proof_id),
                seal_endpoint: config.seal_endpoint.clone(),
                seal_response: None,
            }))
        }
    }
}

/// Validate meter record data
fn validate_meter_record(record: &MeterRecord) -> Result<(), String> {
    // Check required fields
    if record.meter_id.is_empty() {
        return Err("meter_id cannot be empty".to_string());
    }
    
    if record.nonce.is_empty() {
        return Err("nonce cannot be empty".to_string());
    }
    
    // Validate timestamp (not too old, not in future)
    let now = Utc::now().timestamp_millis();
    let max_age_ms = 24 * 60 * 60 * 1000; // 24 hours
    let max_future_ms = 5 * 60 * 1000; // 5 minutes
    
    if record.timestamp < (now - max_age_ms) {
        return Err("timestamp too old (>24 hours)".to_string());
    }
    
    if record.timestamp > (now + max_future_ms) {
        return Err("timestamp too far in future (>5 minutes)".to_string());
    }
    
    // Validate kWh delta (must be positive and reasonable)
    if record.kwh_delta <= 0.0 {
        return Err("kwh_delta must be positive".to_string());
    }
    
    if record.kwh_delta > 1000.0 {
        return Err("kwh_delta too large (>1000 kWh)".to_string());
    }
    
    // Validate meter_id format
    if record.meter_id.len() > 100 {
        return Err("meter_id too long (>100 characters)".to_string());
    }
    
    // Validate nonce format (should be hex)
    if !record.nonce.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("nonce must be hexadecimal".to_string());
    }
    
    if record.nonce.len() != 32 {
        return Err("nonce must be 32 hex characters".to_string());
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_meter_record_valid() {
        let record = MeterRecord {
            meter_id: "test_meter_001".to_string(),
            timestamp: Utc::now().timestamp_millis(),
            kwh_delta: 1.5,
            nonce: "1234567890abcdef1234567890abcdef".to_string(),
        };
        
        assert!(validate_meter_record(&record).is_ok());
    }

    #[test]
    fn test_validate_meter_record_empty_meter_id() {
        let record = MeterRecord {
            meter_id: "".to_string(),
            timestamp: Utc::now().timestamp_millis(),
            kwh_delta: 1.5,
            nonce: "1234567890abcdef1234567890abcdef".to_string(),
        };
        
        assert!(validate_meter_record(&record).is_err());
    }

    #[test]
    fn test_validate_meter_record_negative_kwh() {
        let record = MeterRecord {
            meter_id: "test_meter".to_string(),
            timestamp: Utc::now().timestamp_millis(),
            kwh_delta: -1.0,
            nonce: "1234567890abcdef1234567890abcdef".to_string(),
        };
        
        assert!(validate_meter_record(&record).is_err());
    }

    #[test]
    fn test_validate_meter_record_invalid_nonce() {
        let record = MeterRecord {
            meter_id: "test_meter".to_string(),
            timestamp: Utc::now().timestamp_millis(),
            kwh_delta: 1.5,
            nonce: "invalid_nonce".to_string(),
        };
        
        assert!(validate_meter_record(&record).is_err());
    }
}
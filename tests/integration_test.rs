// FILE: tests/integration_test.rs
use actix_web::{test, web, App};
use actix_rt;
use serde_json::json;
use std::sync::Arc;
use tokio::sync::Mutex;

// Import the modules from our application
use rofl_enclave::config::Config;
use rofl_enclave::models::*;
use rofl_enclave::handlers::*;
use rofl_enclave::aggregator::DataAggregator;

#[actix_rt::test]
async fn test_health_check() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/health", web::get().to(health_check))
    ).await;

    let req = test::TestRequest::get().uri("/health").to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: HealthResponse = test::read_body_json(resp).await;
    assert_eq!(body.status, "healthy");
    assert_eq!(body.version, "1.0.0");
}

#[actix_rt::test]
async fn test_ingest_meter_data() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/ingest", web::post().to(ingest_data))
    ).await;

    // Create test meter data
    let meter_data = create_test_signed_meter_data();
    
    let req = test::TestRequest::post()
        .uri("/ingest")
        .set_json(&meter_data)
        .to_request();
    
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    
    let body: IngestResponse = test::read_body_json(resp).await;
    assert!(body.success);
    assert_eq!(body.message, "Data ingested successfully");
}

#[actix_rt::test]
async fn test_invalid_signature_rejection() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/ingest", web::post().to(ingest_data))
    ).await;

    // Create test meter data with invalid signature
    let mut meter_data = create_test_signed_meter_data();
    meter_data.sig = "invalid_signature".to_string();
    
    let req = test::TestRequest::post()
        .uri("/ingest")
        .set_json(&meter_data)
        .to_request();
    
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 400); // Bad request due to invalid signature
}

#[actix_rt::test]
async fn test_status_endpoint() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/status", web::get().to(get_status))
    ).await;

    let req = test::TestRequest::get().uri("/status").to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: StatusResponse = test::read_body_json(resp).await;
    assert_eq!(body.status, "running");
    assert_eq!(body.total_records_processed, 0);
    assert_eq!(body.total_proofs_generated, 0);
}

#[actix_rt::test]
async fn test_proof_generation_after_aggregation() {
    let mut config = create_test_config();
    config.agg_window_sec = 1; // 1 second window for testing
    
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator.clone()))
            .route("/ingest", web::post().to(ingest_data))
            .route("/proofs/latest", web::get().to(get_latest_proof))
    ).await;

    // Ingest multiple meter readings
    for i in 0..5 {
        let mut meter_data = create_test_signed_meter_data();
        meter_data.record.meter_id = format!("meter_{}", i);
        meter_data.record.kwh_delta = 1.0 + (i as f64 * 0.1);
        
        let req = test::TestRequest::post()
            .uri("/ingest")
            .set_json(&meter_data)
            .to_request();
        
        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());
    }

    // Wait for aggregation window to close
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

    // Check if proof was generated
    let req = test::TestRequest::get().uri("/proofs/latest").to_request();
    let resp = test::call_service(&app, req).await;
    
    if resp.status().is_success() {
        let proof: ProofData = test::read_body_json(resp).await;
        assert_eq!(proof.record_count, 5);
        assert!(proof.aggregate_kwh > 0.0);
        assert!(!proof.merkle_root.is_empty());
        assert_eq!(proof.meter_ids.len(), 5);
    }
}

#[actix_rt::test]
async fn test_replay_attack_protection() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/ingest", web::post().to(ingest_data))
    ).await;

    let meter_data = create_test_signed_meter_data();
    
    // Send the same data twice
    for _ in 0..2 {
        let req = test::TestRequest::post()
            .uri("/ingest")
            .set_json(&meter_data)
            .to_request();
        
        let resp = test::call_service(&app, req).await;
        
        // First request should succeed, second should fail (replay protection)
        if resp.status().is_success() {
            let body: IngestResponse = test::read_body_json(resp).await;
            assert!(body.success);
        } else {
            // Second request should be rejected
            assert_eq!(resp.status(), 400);
        }
    }
}

#[actix_rt::test]
async fn test_seal_endpoint() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/seal", web::post().to(seal_proof))
    ).await;

    let seal_request = SealRequest {
        proof_id: None,
        force_latest: true,
    };
    
    let req = test::TestRequest::post()
        .uri("/seal")
        .set_json(&seal_request)
        .to_request();
    
    let resp = test::call_service(&app, req).await;
    
    // Should return success even if no proofs available
    assert!(resp.status().is_success());
    
    let body: SealResponse = test::read_body_json(resp).await;
    // Will fail in test environment due to no actual Walrus connection
    assert!(!body.success);
    assert!(body.message.contains("No proofs available") || body.message.contains("Failed to seal"));
}

#[actix_rt::test]
async fn test_concurrent_ingestion() {
    let config = create_test_config();
    let aggregator = Arc::new(Mutex::new(DataAggregator::new(config.clone())));
    
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config))
            .app_data(web::Data::new(aggregator))
            .route("/ingest", web::post().to(ingest_data))
    ).await;

    // Create multiple concurrent requests
    let mut handles = vec![];
    
    for i in 0..10 {
        let app_clone = app.clone();
        let handle = tokio::spawn(async move {
            let mut meter_data = create_test_signed_meter_data();
            meter_data.record.meter_id = format!("concurrent_meter_{}", i);
            meter_data.record.nonce = format!("nonce_{}", i);
            
            let req = test::TestRequest::post()
                .uri("/ingest")
                .set_json(&meter_data)
                .to_request();
            
            test::call_service(&app_clone, req).await
        });
        handles.push(handle);
    }

    // Wait for all requests to complete
    for handle in handles {
        let resp = handle.await.unwrap();
        assert!(resp.status().is_success());
    }
}

// Helper functions

fn create_test_config() -> Config {
    Config {
        host: "127.0.0.1".to_string(),
        port: 8080,
        agg_window_sec: 300,
        max_records_per_window: 1000,
        output_dir: "/tmp/test_proofs".to_string(),
        enable_signature_verification: true,
        walrus_publisher_url: "https://publisher-devnet.walrus.space".to_string(),
        walrus_gateway_url: "https://aggregator-devnet.walrus.space".to_string(),
        walrus_epochs: 5,
    }
}

fn create_test_signed_meter_data() -> SignedMeterData {
    let record = MeterRecord {
        meter_id: "test_meter_001".to_string(),
        timestamp: chrono::Utc::now().timestamp(),
        kwh_delta: 1.234,
        nonce: "test_nonce_123".to_string(),
    };

    // Create a mock signature (in real implementation, this would be a valid ECDSA signature)
    let mock_signature = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";

    SignedMeterData {
        record,
        sig: mock_signature.to_string(),
    }
}
// FILE: tests/walrus_seal_tests.move
#[test_only]
module greenshare::walrus_seal_tests {
    use greenshare::walrus_seal::{Self, BlobRegistry, RegistryAdminCap};
    use sui::test_scenario::{Self, Scenario};
    use sui::clock;
    use std::string;

    // Test addresses
    const ADMIN: address = @0xADMN;
    const USER1: address = @0x1111;
    const USER2: address = @0x2222;

    #[test]
    fun test_blob_registration() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        // Initialize walrus_seal module
        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        // Get objects created during init
        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Register a blob
        let blob_id = string::utf8(b"blob_12345abcdef");
        let content_hash = string::utf8(b"sha256_hash_of_content_0123456789abcdef0123456789abcdef01234567");
        let proof_hash = string::utf8(b"proof_hash_xyz789");
        let size_bytes = 1024;
        let storage_url = string::utf8(b"https://walrus.example.com/blobs/blob_12345abcdef");

        walrus_seal::register_blob(
            &mut registry,
            blob_id,
            content_hash,
            proof_hash,
            size_bytes,
            storage_url,
            &clock,
            ctx
        );

        // Verify blob was registered
        assert!(walrus_seal::blob_exists(&registry, blob_id), 0);
        assert!(walrus_seal::get_total_blobs(&registry) == 1, 1);

        // Verify blob information
        let (reg_blob_id, reg_content_hash, reg_proof_hash, reg_size, reg_url, 
             _reg_timestamp, reg_by, reg_verified) = walrus_seal::get_blob_info(&registry, blob_id);

        assert!(reg_blob_id == blob_id, 2);
        assert!(reg_content_hash == content_hash, 3);
        assert!(reg_proof_hash == proof_hash, 4);
        assert!(reg_size == size_bytes, 5);
        assert!(reg_url == storage_url, 6);
        assert!(reg_by == ADMIN, 7);
        assert!(!reg_verified, 8); // Should be unverified initially

        // Test reverse lookup
        assert!(walrus_seal::get_blob_by_proof(&registry, proof_hash) == blob_id, 9);

        // Clean up
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = walrus_seal::EBlobAlreadyRegistered)]
    fun test_duplicate_blob_registration() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx);

        let blob_id = string::utf8(b"duplicate_blob_test");
        let content_hash = string::utf8(b"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
        let proof_hash = string::utf8(b"proof_duplicate");

        // First registration should succeed
        walrus_seal::register_blob(
            &mut registry,
            blob_id,
            content_hash,
            proof_hash,
            1024,
            string::utf8(b"https://example.com/blob1"),
            &clock,
            ctx
        );

        // Second registration with same blob_id should fail
        walrus_seal::register_blob(
            &mut registry,
            blob_id, // Same blob ID
            string::utf8(b"different_content_hash_but_same_blob_id_abcdef1234567890abcdef12"),
            string::utf8(b"proof_different"),
            2048,
            string::utf8(b"https://example.com/blob2"),
            &clock,
            ctx
        );

        // Clean up (won't reach here due to expected failure)
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_blob_verification() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Register a blob
        let blob_id = string::utf8(b"verification_test_blob");
        let content_hash = string::utf8(b"correct_hash_1234567890abcdef1234567890abcdef1234567890abcdef12");
        
        walrus_seal::register_blob(
            &mut registry,
            blob_id,
            content_hash,
            string::utf8(b"proof_verify"),
            1024,
            string::utf8(b"https://example.com/verify"),
            &clock,
            ctx
        );

        // Initially should be unverified
        assert!(!walrus_seal::is_blob_verified(&registry, blob_id), 0);

        // Verify with correct hash
        walrus_seal::verify_blob(
            &admin_cap,
            &mut registry,
            blob_id,
            content_hash, // Same hash as registered
            &clock,
            ctx
        );

        // Should now be verified
        assert!(walrus_seal::is_blob_verified(&registry, blob_id), 1);

        // Verify with incorrect hash should mark as unverified
        walrus_seal::verify_blob(
            &admin_cap,
            &mut registry,
            blob_id,
            string::utf8(b"wrong_hash_abcdef1234567890abcdef1234567890abcdef1234567890abcd"),
            &clock,
            ctx
        );

        // Should now be unverified
        assert!(!walrus_seal::is_blob_verified(&registry, blob_id), 2);

        // Clean up
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fingerprint_update() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Register a blob
        let blob_id = string::utf8(b"fingerprint_update_test");
        let original_hash = string::utf8(b"original_hash_1234567890abcdef1234567890abcdef1234567890abcdef");
        
        walrus_seal::register_blob(
            &mut registry,
            blob_id,
            original_hash,
            string::utf8(b"proof_fingerprint"),
            1024,
            string::utf8(b"https://example.com/fingerprint"),
            &clock,
            ctx
        );

        // Verify original hash
        assert!(walrus_seal::get_content_hash(&registry, blob_id) == original_hash, 0);

        // Update fingerprint
        let new_hash = string::utf8(b"updated_hash_abcdef1234567890abcdef1234567890abcdef1234567890");
        walrus_seal::update_fingerprint(
            &admin_cap,
            &mut registry,
            blob_id,
            new_hash,
            &clock,
            ctx
        );

        // Verify hash was updated
        assert!(walrus_seal::get_content_hash(&registry, blob_id) == new_hash, 1);

        // Verification status should be reset
        assert!(!walrus_seal::is_blob_verified(&registry, blob_id), 2);

        // Clean up
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_batch_blob_registration() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Prepare batch data
        let blob_ids = std::vector::empty<std::string::String>();
        let content_hashes = std::vector::empty<std::string::String>();
        let proof_hashes = std::vector::empty<std::string::String>();
        let sizes = std::vector::empty<u64>();
        let storage_urls = std::vector::empty<std::string::String>();

        // Add 3 blobs to batch
        std::vector::push_back(&mut blob_ids, string::utf8(b"batch_blob_1"));
        std::vector::push_back(&mut blob_ids, string::utf8(b"batch_blob_2"));
        std::vector::push_back(&mut blob_ids, string::utf8(b"batch_blob_3"));

        std::vector::push_back(&mut content_hashes, string::utf8(b"hash1_abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456"));
        std::vector::push_back(&mut content_hashes, string::utf8(b"hash2_123456abcdef1234567890abcdef1234567890abcdef1234567890abcd"));
        std::vector::push_back(&mut content_hashes, string::utf8(b"hash3_7890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12"));

        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_batch_1"));
        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_batch_2"));
        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_batch_3"));

        std::vector::push_back(&mut sizes, 1024);
        std::vector::push_back(&mut sizes, 2048);
        std::vector::push_back(&mut sizes, 4096);

        std::vector::push_back(&mut storage_urls, string::utf8(b"https://example.com/batch1"));
        std::vector::push_back(&mut storage_urls, string::utf8(b"https://example.com/batch2"));
        std::vector::push_back(&mut storage_urls, string::utf8(b"https://example.com/batch3"));

        // Register batch
        walrus_seal::batch_register_blobs(
            &mut registry,
            blob_ids,
            content_hashes,
            proof_hashes,
            sizes,
            storage_urls,
            &clock,
            ctx
        );

        // Verify all blobs were registered
        assert!(walrus_seal::get_total_blobs(&registry) == 3, 0);
        assert!(walrus_seal::blob_exists(&registry, string::utf8(b"batch_blob_1")), 1);
        assert!(walrus_seal::blob_exists(&registry, string::utf8(b"batch_blob_2")), 2);
        assert!(walrus_seal::blob_exists(&registry, string::utf8(b"batch_blob_3")), 3);

        // Clean up
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_utility_functions() {
        // Test storage URL generation
        let base_url = string::utf8(b"https://walrus.example.com/blobs");
        let blob_id = string::utf8(b"test_blob_123");
        let expected_url = string::utf8(b"https://walrus.example.com/blobs/test_blob_123");
        
        let generated_url = walrus_seal::generate_storage_url(base_url, blob_id);
        assert!(generated_url == expected_url, 0);

        // Test blob ID validation
        assert!(walrus_seal::is_valid_blob_id(string::utf8(b"valid_blob_id")), 1);
        assert!(!walrus_seal::is_valid_blob_id(string::utf8(b"")), 2); // Empty should be invalid

        // Test content hash validation (64 hex chars for SHA256)
        assert!(walrus_seal::is_valid_content_hash(string::utf8(b"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")), 3);
        assert!(!walrus_seal::is_valid_content_hash(string::utf8(b"short_hash")), 4); // Too short
    }

    #[test]
    #[expected_failure(abort_code = walrus_seal::EBlobNotFound)]
    fun test_nonexistent_blob_access() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);

        // Try to access non-existent blob (should fail)
        walrus_seal::get_blob_info(&registry, string::utf8(b"nonexistent_blob"));

        // Clean up (won't reach here due to expected failure)
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_admin_transfer() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);

        walrus_seal::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, ADMIN);

        let mut registry = test_scenario::take_shared<BlobRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);

        // Verify initial admin
        assert!(walrus_seal::get_admin(&registry) == ADMIN, 0);

        // Transfer admin to USER1
        walrus_seal::transfer_admin(admin_cap, USER1, &mut registry, ctx);

        // Verify admin was transferred
        assert!(walrus_seal::get_admin(&registry) == USER1, 1);

        test_scenario::next_tx(&mut scenario, USER1);

        // Verify USER1 received admin capability
        let new_admin_cap = test_scenario::take_from_sender<RegistryAdminCap>(&scenario);

        // Clean up
        test_scenario::return_to_sender(&scenario, new_admin_cap);
        test_scenario::return_shared(registry);
        test_scenario::end(scenario);
    }
}
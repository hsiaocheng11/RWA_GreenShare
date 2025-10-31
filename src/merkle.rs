// FILE: src/merkle.rs
use sha3::{Keccak256, Digest};
use hex;

#[derive(Debug, Clone)]
pub struct MerkleTree {
    pub root: String,
    pub leaves: Vec<String>,
    pub tree: Vec<Vec<String>>,
}

impl MerkleTree {
    /// Build Merkle tree from record hashes
    pub fn new(mut hashes: Vec<String>) -> Result<Self, Box<dyn std::error::Error>> {
        if hashes.is_empty() {
            return Err("Cannot build Merkle tree from empty hash list".into());
        }

        let leaves = hashes.clone();
        let mut tree = vec![hashes.clone()];

        // Build tree bottom-up
        while hashes.len() > 1 {
            // If odd number of hashes, duplicate the last one
            if hashes.len() % 2 == 1 {
                hashes.push(hashes.last().unwrap().clone());
            }

            let mut next_level = Vec::new();
            for chunk in hashes.chunks(2) {
                let combined_hash = Self::hash_pair(&chunk[0], &chunk[1])?;
                next_level.push(combined_hash);
            }

            tree.push(next_level.clone());
            hashes = next_level;
        }

        let root = hashes.into_iter().next().unwrap();

        Ok(MerkleTree {
            root,
            leaves,
            tree,
        })
    }

    /// Hash two strings together using Keccak256
    fn hash_pair(left: &str, right: &str) -> Result<String, Box<dyn std::error::Error>> {
        let mut hasher = Keccak256::new();
        
        // Ensure consistent ordering by comparing lexicographically
        if left <= right {
            hasher.update(hex::decode(left)?);
            hasher.update(hex::decode(right)?);
        } else {
            hasher.update(hex::decode(right)?);
            hasher.update(hex::decode(left)?);
        }
        
        let result = hasher.finalize();
        Ok(hex::encode(result))
    }

    /// Generate Merkle proof for a specific leaf
    pub fn generate_proof(&self, leaf_index: usize) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        if leaf_index >= self.leaves.len() {
            return Err("Leaf index out of bounds".into());
        }

        let mut proof = Vec::new();
        let mut current_index = leaf_index;

        // Traverse up the tree, collecting sibling hashes
        for level in &self.tree[..self.tree.len() - 1] {
            let sibling_index = if current_index % 2 == 0 {
                current_index + 1
            } else {
                current_index - 1
            };

            if sibling_index < level.len() {
                proof.push(level[sibling_index].clone());
            }

            current_index /= 2;
        }

        Ok(proof)
    }

    /// Verify a Merkle proof
    pub fn verify_proof(
        leaf_hash: &str,
        proof: &[String],
        root: &str,
        leaf_index: usize,
    ) -> Result<bool, Box<dyn std::error::Error>> {
        let mut current_hash = leaf_hash.to_string();
        let mut current_index = leaf_index;

        for sibling_hash in proof {
            current_hash = if current_index % 2 == 0 {
                Self::hash_pair(&current_hash, sibling_hash)?
            } else {
                Self::hash_pair(sibling_hash, &current_hash)?
            };
            current_index /= 2;
        }

        Ok(current_hash == root)
    }

    /// Get tree statistics
    pub fn stats(&self) -> MerkleStats {
        MerkleStats {
            total_leaves: self.leaves.len(),
            tree_height: self.tree.len(),
            root_hash: self.root.clone(),
        }
    }
}

#[derive(Debug)]
pub struct MerkleStats {
    pub total_leaves: usize,
    pub tree_height: usize,
    pub root_hash: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_leaf_tree() {
        let hashes = vec!["abcd".to_string()];
        let tree = MerkleTree::new(hashes.clone()).unwrap();
        assert_eq!(tree.root, "abcd");
    }

    #[test]
    fn test_two_leaf_tree() {
        let hashes = vec![
            "a".repeat(64),
            "b".repeat(64),
        ];
        let tree = MerkleTree::new(hashes).unwrap();
        assert_eq!(tree.leaves.len(), 2);
        assert_ne!(tree.root, tree.leaves[0]);
    }

    #[test]
    fn test_odd_number_leaves() {
        let hashes = vec![
            "a".repeat(64),
            "b".repeat(64),
            "c".repeat(64),
        ];
        let tree = MerkleTree::new(hashes).unwrap();
        assert_eq!(tree.leaves.len(), 3);
    }

    #[test]
    fn test_proof_generation_and_verification() {
        let hashes = vec![
            "a".repeat(64),
            "b".repeat(64),
            "c".repeat(64),
            "d".repeat(64),
        ];
        let tree = MerkleTree::new(hashes.clone()).unwrap();
        
        // Generate proof for first leaf
        let proof = tree.generate_proof(0).unwrap();
        
        // Verify proof
        let is_valid = MerkleTree::verify_proof(
            &tree.leaves[0],
            &proof,
            &tree.root,
            0,
        ).unwrap();
        
        assert!(is_valid);
    }

    #[test]
    fn test_hash_pair_ordering() {
        let hash1 = "a".repeat(64);
        let hash2 = "b".repeat(64);
        
        let result1 = MerkleTree::hash_pair(&hash1, &hash2).unwrap();
        let result2 = MerkleTree::hash_pair(&hash2, &hash1).unwrap();
        
        // Should be the same due to consistent ordering
        assert_eq!(result1, result2);
    }

    #[test]
    fn test_empty_tree() {
        let hashes = vec![];
        let result = MerkleTree::new(hashes);
        assert!(result.is_err());
    }
}
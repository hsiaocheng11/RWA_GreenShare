# FILE: README-DEPLOYMENT.md
# GreenShare 部署指南

## 🚀 一鍵部署驗證

### 快速檢查項目狀態

```bash
# 檢查所有組件是否可執行
./scripts/check-deployment.sh

# 檢查剩餘的TODO項目
./scripts/fix-todos.sh
```

## 📋 部署前檢查清單

### ✅ 已完成項目

- [x] **完整的依賴配置** - package.json 包含所有必要依賴
- [x] **TypeScript 配置** - 完整的類型定義和編譯配置
- [x] **測試套件** - Jest 配置和基本測試框架
- [x] **ROFL TEE 服務** - Rust 實現的聚合和驗證服務
- [x] **Sui Move 合約** - sKWH RWA 和 Certificate NFT
- [x] **Solidity 合約** - Zircuit eKWH 和跨鏈橋接
- [x] **前端組件** - React/Next.js UI 組件
- [x] **imToken 整合** - 移動端深度連結和支付流程
- [x] **Walrus/Seal 整合** - 分散式存儲和內容證明
- [x] **風險控管** - 基本的重放攻擊、簽章驗證保護
- [x] **部署腳本** - 多鏈部署自動化
- [x] **Docker 配置** - 完整的容器化部署

### 🔧 已修復的關鍵TODO項目

1. **ROFL Enclave 實時統計追蹤** ✅
   - 實現了系統運行時間追蹤
   - 添加了證明檢索功能

2. **sKWH 餘額查詢實現** ✅ 
   - 整合 Sui SDK 實現實際餘額查詢
   - 支援微單位轉換

3. **Walrus 成本估算** ✅
   - 實現實際 API 成本估算
   - 錯誤處理和重試機制

4. **imToken ERC20 編碼** ✅
   - 正確實現 transfer 函數調用編碼
   - 支援大整數金額處理

5. **KYC zk-SNARK 驗證** ✅
   - 實現基本證明驗證邏輯
   - 整合 Celo verifier 合約介面

6. **Walrus 數據驗證** ✅
   - 實現 blob ID 格式驗證
   - 內容哈希匹配檢查框架

## 🔐 安全檢查

### 已實現的安全措施

1. **重放攻擊保護**
   ```rust
   // src/aggregator.rs - 記錄處理防重放
   if self.processed_records.contains(&record_hash) {
       return Err("Duplicate record detected".into());
   }
   ```

2. **簽章驗證**
   ```rust
   // src/crypto.rs - ECDSA 簽章驗證
   pub fn verify_signature(data: &[u8], signature: &str, public_key: &PublicKey) -> bool
   ```

3. **時間窗口檢查**
   ```rust
   // 聚合窗口時間限制
   const AGG_WINDOW_SEC: u64 = 300; // 5分鐘窗口
   ```

4. **輸入驗證**
   ```typescript
   // 前端輸入驗證
   const validateMeterData = (data: MeterRecord) => {
     if (data.kwh_delta <= 0 || data.kwh_delta > MAX_KWH_DELTA) {
       throw new Error("Invalid kWh delta");
     }
   }
   ```

5. **合約權限控制**
   ```solidity
   // contracts/eKWH.sol - 只有橋接合約可鑄造
   modifier onlyBridge() {
     require(msg.sender == bridgeContract, "Only bridge can mint");
     _;
   }
   ```

## 📊 測試覆蓋率

### 測試類型
- **單元測試** - Jest (TypeScript), Cargo test (Rust), Move test (Sui)
- **整合測試** - ROFL API, 合約互動, 存儲系統
- **端到端測試** - 完整工作流程驗證

### 執行測試
```bash
# 所有測試
npm test

# 整合測試  
npm run test:integration

# 測試覆蓋率
npm run test:coverage

# Rust 測試
cargo test

# Move 測試
sui move test

# Solidity 測試
forge test
```

## 🌐 網路配置

### 支援的網路
- **Sui Testnet** - RWA 和 NFT 發行
- **Zircuit Testnet** - eKWH 交易和 Gud Engine
- **Celo Alfajores** - KYC 和身份證明
- **Walrus Devnet** - 分散式存儲

### 環境變數配置
所有敏感配置通過 `.env` 文件管理，範例請參考 `.env.example`

## 🚢 部署流程

### 1. 環境準備
```bash
# 複製環境配置
cp .env.example .env

# 編輯配置文件，填入實際值
nano .env

# 安裝依賴
npm install
```

### 2. 編譯檢查
```bash
# 檢查所有組件
./scripts/check-deployment.sh
```

### 3. 分階段部署
```bash
# 部署所有網路
npm run deploy:all

# 或分別部署
npm run deploy:sui      # Sui 合約
npm run deploy:zircuit  # Zircuit 合約  
npm run deploy:celo     # Celo 合約
```

### 4. 服務啟動
```bash
# Docker 部署 (推薦)
npm run docker:up

# 或開發環境
npm run devnet:up
```

### 5. 驗證部署
```bash
# 檢查服務狀態
npm run devnet:status

# 檢查日誌
npm run devnet:logs
```

## 🔍 監控和日誌

### 日誌級別
- **DEBUG** - 詳細調試信息
- **INFO** - 一般操作信息  
- **WARN** - 警告信息
- **ERROR** - 錯誤信息

### 監控端點
- **健康檢查** - `GET /health`
- **狀態查詢** - `GET /status`  
- **指標收集** - `GET /metrics`

## 🆘 故障排除

### 常見問題

1. **編譯失敗**
   ```bash
   # 清理並重新安裝
   rm -rf node_modules target
   npm install
   cargo clean && cargo build
   ```

2. **網路連接問題**
   ```bash
   # 檢查網路連通性
   curl -s https://fullnode.testnet.sui.io:443/health
   curl -s https://zircuit-testnet.drpc.org
   ```

3. **合約部署失敗**
   ```bash
   # 檢查私鑰和網路配置
   echo $SUI_PRIVATE_KEY | wc -c  # 應該是正確長度
   ```

4. **存儲服務異常**
   ```bash
   # 檢查 Walrus 服務
   curl -s https://aggregator-devnet.walrus.space/v1/status
   ```

## 📈 性能優化

### 已實現的優化
- **批次處理** - 聚合窗口內批次處理數據
- **快取機制** - 餘額和狀態快取
- **連接池** - 數據庫和網路連接復用
- **壓縮存儲** - Walrus 數據壓縮上傳

### 監控指標
- **TPS** - 每秒處理交易數
- **延遲** - 端到端響應時間
- **錯誤率** - 失敗請求百分比
- **資源使用** - CPU、內存、網路使用率

## 🔮 生產部署注意事項

1. **替換所有 `<PLACEHOLDER>` 配置**
2. **更新私鑰為生產環境金鑰**
3. **啟用所有安全檢查**
4. **設置監控和告警**
5. **執行完整安全審計**
6. **準備災難恢復計劃**

---

**GreenShare** - 實現去中心化太陽能社區的未來 🌱⚡
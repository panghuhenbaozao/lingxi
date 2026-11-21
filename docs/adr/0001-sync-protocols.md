# ADR 0001：同步冲突策略——版本向量 + LWW，不采用 CRDT

- 状态：已采纳（2026-11-22）
- 决策人：项目所有者全权委托
- 关联代码：`Shared/Services/SyncProtocols.swift`

## 背景

灵犀 v4.0 路线图包含跨设备同步（设置/词库/皮肤）。多端并发写入需要冲突解决策略。
候选方案：
1. CRDT 库（Automerge/Yjs）
2. 版本向量 + LWW（Last-Writer-Wins）寄存器
3. 服务端时间戳覆盖

## 调研结论

- **Automerge**（https://github.com/automerge/automerge）：定位是 local-first **协作文档**（多人共编笔记类场景），核心为 Rust 实现，经 WASM/C FFI 暴露。引入 iOS 需跨语言桥接，包体积与调试成本高。其价值在于**字符级**合并——灵犀无此需求。
- **灵犀同步数据天然是键值对**：设置项（一个开关一个 key）、词库条目（一条短语一个 key）。冲突语义即『同一字段谁说了算』，LWW 完全覆盖。
- **成熟先例**：Bitwarden/Vaultwarden（密码库同步）、Hamster 仓输入法（词库导入导出）均采用简单全序/覆盖策略，无一家在输入法场景使用 CRDT。

## 决策

采用**版本向量 + LWW**：
- 每条记录携带 `(lamport_ts, device_id)`；
- 合并全序规则：lamport_ts 大者胜，相同则 device_id 字典序大者胜（`SyncChange.wins(over:)`）；
- 删除走墓碑标记（tombstone），墓碑保留 90 天后可物理清理；
- 增量同步按每设备水位线（nextCursor）拉取；
- Lamport 时钟在本地写入时递增，收到远端记录时 `max(local, remote) + 1`。

## 后果

- 正：实现简单、可测试、服务端零逻辑（只存转发）、包体积零负担。
- 负：并发编辑同一词库条目时后写者覆盖先写者（键值语义下可接受；若未来出现『多人共建词库』的字符级协作需求，届时重新评估 CRDT 并新增 ADR）。
- 中性：Lamport 时钟不与真实时间对齐，UI 展示『最后修改时间』需另存墙上时钟字段（schemaVersion ≥ 2 时补充）。

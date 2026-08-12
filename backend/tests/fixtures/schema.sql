-- =====================================================================
-- Conver System 数据库 schema 静态快照（快照即契约）
--
-- 单一来源：本文件是 backend/tests/test_migrate_data.py `_make_db` 的建表
-- 语句来源（替换历史手抄 DDL），也是漂移检测测试
-- backend/tests/test_schema_snapshot.py 的比对基准。
--
-- 铁律：任何 schema 变更（ORM 模型新增/修改列、类型、索引）都必须同步
-- 更新本文件；未同步则漂移检测测试显式失败（静默失真 → 显式失败）。
--
-- 来源：一次性从 ORM 元数据 dump（Base.metadata.create_all → sqlite DDL）
-- 后人工核验落盘（对照 app/models/*.py 与 docs/architecture.md）。
-- 对照结论：characters 全 19 列（含 created_at/updated_at——历史手抄
-- 17 列漂移缺的正是这两列）；conversations 为 model_provider/model_name
-- （历史手抄漂移成 provider/model）；含 3 条索引（name / character_id /
-- conversation_id），不含任何 sqlite_* 内部表。
-- =====================================================================

CREATE TABLE characters (
	id INTEGER NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	description TEXT, 
	personality TEXT, 
	scenario TEXT, 
	first_mes TEXT, 
	mes_example TEXT, 
	system_prompt TEXT, 
	post_history_instructions TEXT, 
	alternate_greetings JSON, 
	tags JSON, 
	creator VARCHAR(100), 
	version VARCHAR(50), 
	creator_notes JSON, 
	extensions JSON, 
	avatar TEXT, 
	temperature FLOAT, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);

CREATE TABLE conversations (
	id INTEGER NOT NULL, 
	character_id INTEGER NOT NULL, 
	title VARCHAR(200), 
	model_provider VARCHAR(50), 
	model_name VARCHAR(100), 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE
);

CREATE TABLE messages (
	id INTEGER NOT NULL, 
	conversation_id INTEGER NOT NULL, 
	role VARCHAR(9) NOT NULL, 
	content TEXT NOT NULL, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	FOREIGN KEY(conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
);

CREATE TABLE settings (
	"key" VARCHAR(100) NOT NULL, 
	value TEXT, 
	PRIMARY KEY ("key")
);

CREATE INDEX ix_characters_name ON characters (name);

CREATE INDEX ix_conversations_character_id ON conversations (character_id);

CREATE INDEX ix_messages_conversation_id ON messages (conversation_id);

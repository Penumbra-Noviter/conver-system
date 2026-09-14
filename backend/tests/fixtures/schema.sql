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
-- 对照结论：characters 全 23 列（含 created_at/updated_at + SP-1 采样四列
-- top_p/presence_penalty/frequency_penalty/max_tokens）；conversations 为 model_provider/model_name
-- （历史手抄漂移成 provider/model）；lorebook_entries 为 WL-1 世界书条目表
-- （含 4 条 CHECK 边界约束 + FK 级联）；message_swipes 为 MS-1 候选表
-- （(message_id, index) 唯一 + messages.active_swipe_index 列自愈迁移）；含 5 条索引
-- （name / character_id / conversation_id / lorebook_entries_character_id /
-- message_swipes_message_id），不含任何 sqlite_* 内部表。
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
	top_p FLOAT, 
	presence_penalty FLOAT, 
	frequency_penalty FLOAT, 
	max_tokens INTEGER, 
	prompt_mode VARCHAR(8) DEFAULT 'simple' NOT NULL, 
	expert_prompt TEXT DEFAULT '' NOT NULL, 
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
	parent_conversation_id INTEGER, 
	branch_from_message_id INTEGER, 
	branch_title VARCHAR(200), 
	preset_dialogue TEXT, 
	PRIMARY KEY (id), 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE
);

CREATE TABLE messages (
	id INTEGER NOT NULL, 
	conversation_id INTEGER NOT NULL, 
	role VARCHAR(9) NOT NULL, 
	content TEXT NOT NULL, 
	active_swipe_index INTEGER DEFAULT '0' NOT NULL, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	FOREIGN KEY(conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
);

CREATE TABLE message_swipes (
	id INTEGER NOT NULL, 
	message_id INTEGER NOT NULL, 
	"index" INTEGER NOT NULL, 
	content TEXT NOT NULL, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_message_swipes_message_index UNIQUE (message_id, "index"), 
	FOREIGN KEY(message_id) REFERENCES messages (id) ON DELETE CASCADE
);

CREATE TABLE settings (
	"key" VARCHAR(100) NOT NULL, 
	value TEXT, 
	PRIMARY KEY ("key")
);

CREATE TABLE lorebook_entries (
	id INTEGER NOT NULL, 
	character_id INTEGER NOT NULL, 
	title VARCHAR(200), 
	keys TEXT DEFAULT '[]' NOT NULL, 
	content TEXT NOT NULL, 
	constant BOOLEAN, 
	"order" INTEGER, 
	probability INTEGER, 
	group_name VARCHAR(100), 
	group_weight INTEGER, 
	match_mode VARCHAR(8), 
	position VARCHAR(16), 
	depth INTEGER, 
	source VARCHAR(16), 
	enabled BOOLEAN, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_lorebook_entries_order CHECK ("order" >= 0 AND "order" <= 9999), 
	CONSTRAINT ck_lorebook_entries_probability CHECK (probability >= 1 AND probability <= 100), 
	CONSTRAINT ck_lorebook_entries_group_weight CHECK (group_weight >= 1 AND group_weight <= 100), 
	CONSTRAINT ck_lorebook_entries_depth CHECK (depth >= 0 AND depth <= 20), 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE
);

CREATE TABLE cg_images (
	id INTEGER NOT NULL, 
	character_id INTEGER NOT NULL, 
	conversation_id INTEGER, 
	message_id INTEGER, 
	url TEXT NOT NULL, 
	weight INTEGER DEFAULT '100' NOT NULL, 
	group_name VARCHAR(100), 
	is_special BOOLEAN, 
	unlocked BOOLEAN, 
	unlock_hint TEXT, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE, 
	FOREIGN KEY(conversation_id) REFERENCES conversations (id) ON DELETE SET NULL, 
	FOREIGN KEY(message_id) REFERENCES messages (id) ON DELETE SET NULL
);

CREATE TABLE image_tasks (
	id INTEGER NOT NULL, 
	conversation_id INTEGER NOT NULL, 
	character_id INTEGER NOT NULL, 
	message_id INTEGER, 
	provider VARCHAR(50), 
	params TEXT NOT NULL, 
	status VARCHAR(20), 
	result_url TEXT, 
	error TEXT, 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	completed_at DATETIME, 
	PRIMARY KEY (id), 
	FOREIGN KEY(conversation_id) REFERENCES conversations (id) ON DELETE CASCADE, 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE, 
	FOREIGN KEY(message_id) REFERENCES messages (id) ON DELETE SET NULL
);

CREATE TABLE mods (
	id INTEGER NOT NULL, 
	name VARCHAR(200) NOT NULL, 
	description TEXT, 
	target_area VARCHAR(16) NOT NULL, 
	payload TEXT NOT NULL, 
	version VARCHAR(50), 
	source VARCHAR(16), 
	created_at DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);

CREATE TABLE mod_bindings (
	id INTEGER NOT NULL, 
	character_id INTEGER NOT NULL, 
	mod_id INTEGER NOT NULL, 
	enabled BOOLEAN NOT NULL, 
	sort_order INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_mod_bindings_character_mod UNIQUE (character_id, mod_id), 
	FOREIGN KEY(character_id) REFERENCES characters (id) ON DELETE CASCADE, 
	FOREIGN KEY(mod_id) REFERENCES mods (id) ON DELETE CASCADE
);

CREATE INDEX ix_characters_name ON characters (name);

CREATE INDEX ix_cg_images_character_id ON cg_images (character_id);

CREATE INDEX ix_cg_images_conversation_id ON cg_images (conversation_id);

CREATE INDEX ix_conversations_character_id ON conversations (character_id);

CREATE INDEX ix_image_tasks_conversation_id ON image_tasks (conversation_id);

CREATE INDEX ix_lorebook_entries_character_id ON lorebook_entries (character_id);

CREATE INDEX ix_message_swipes_message_id ON message_swipes (message_id);

CREATE INDEX ix_messages_conversation_id ON messages (conversation_id);

CREATE INDEX ix_mod_bindings_character_id ON mod_bindings (character_id);

CREATE INDEX ix_mod_bindings_mod_id ON mod_bindings (mod_id);

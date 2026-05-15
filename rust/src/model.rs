use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceConfig {
    pub version: u32,
    pub config_dir: String,
    pub selected_session: usize,
    pub sessions: Vec<Session>,
}

impl WorkspaceConfig {
    pub fn default_for_dir(config_dir: impl Into<String>, shell: impl Into<String>) -> Self {
        Self {
            version: 1,
            config_dir: config_dir.into(),
            selected_session: 0,
            sessions: vec![Session {
                name: "Default".to_string(),
                root: PaneNode::Leaf(Pane {
                    id: "leaf-root".to_string(),
                    title: "Pane 1".to_string(),
                    shell: shell.into(),
                    executable: None,
                    command: None,
                    working_dir: None,
                    args: Vec::new(),
                }),
            }],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub name: String,
    pub root: PaneNode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum PaneNode {
    Leaf(Pane),
    Split {
        id: String,
        direction: SplitDirection,
        ratio: f32,
        first: Box<PaneNode>,
        second: Box<PaneNode>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pane {
    pub id: String,
    pub title: String,
    pub shell: String,
    pub executable: Option<String>,
    pub command: Option<String>,
    pub working_dir: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SplitDirection {
    Horizontal,
    Vertical,
}


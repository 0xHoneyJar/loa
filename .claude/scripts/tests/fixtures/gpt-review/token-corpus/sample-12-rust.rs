use std::collections::HashMap;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct RouteConfig {
    pub backend: String,
    pub conditions: Vec<String>,
    pub fail_mode: FailMode,
    pub timeout: Duration,
    pub retries: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum FailMode {
    Fallthrough,
    HardFail,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Verdict {
    Approved,
    ChangesRequired,
    DecisionNeeded,
    Skipped,
}

pub struct ReviewResult {
    pub verdict: Verdict,
    pub findings: Vec<Finding>,
    pub summary: String,
}

pub struct Finding {
    pub severity: String,
    pub file: String,
    pub line: usize,
    pub message: String,
}

pub struct RouteTable {
    routes: Vec<RouteConfig>,
    backends: HashMap<String, Box<dyn Fn(&str) -> Result<ReviewResult, String>>>,
    conditions: HashMap<String, Box<dyn Fn() -> bool>>,
}

impl RouteTable {
    pub fn new() -> Self {
        Self {
            routes: Vec::new(),
            backends: HashMap::new(),
            conditions: HashMap::new(),
        }
    }

    pub fn add_route(&mut self, config: RouteConfig) {
        self.routes.push(config);
    }

    pub fn register_backend<F>(&mut self, name: &str, handler: F)
    where
        F: Fn(&str) -> Result<ReviewResult, String> + 'static,
    {
        self.backends.insert(name.to_string(), Box::new(handler));
    }

    pub fn execute(&self, input: &str) -> Result<ReviewResult, String> {
        for route in &self.routes {
            let conditions_met = route
                .conditions
                .iter()
                .all(|c| self.conditions.get(c).map_or(false, |f| f()));

            if !conditions_met {
                continue;
            }

            let handler = match self.backends.get(&route.backend) {
                Some(h) => h,
                None => {
                    if route.fail_mode == FailMode::HardFail {
                        return Err(format!("Unknown backend: {}", route.backend));
                    }
                    continue;
                }
            };

            for attempt in 0..=route.retries {
                match handler(input) {
                    Ok(result) => return Ok(result),
                    Err(e) => {
                        eprintln!(
                            "Backend {} attempt {} failed: {}",
                            route.backend,
                            attempt + 1,
                            e
                        );
                        if attempt == route.retries && route.fail_mode == FailMode::HardFail {
                            return Err(e);
                        }
                    }
                }
            }
        }

        Err("All routes exhausted".to_string())
    }
}

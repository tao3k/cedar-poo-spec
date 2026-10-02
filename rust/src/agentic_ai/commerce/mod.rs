//! Typed mandate, offer, admission and shared-budget contracts for agentic AI commerce.

#[cfg(feature = "agentic-ai-commerce-admission")]
pub mod admission;
#[cfg(feature = "agentic-ai-commerce-budget-commit")]
pub mod budget_commit;
#[cfg(feature = "agentic-ai-commerce-consumption")]
pub mod consumption;
#[cfg(feature = "agentic-ai-commerce-credential")]
pub mod credential;
#[cfg(feature = "agentic-ai-commerce-projection")]
pub mod projection;
#[cfg(feature = "agentic-ai-commerce-consumption")]
pub mod provider;
pub mod signatures;

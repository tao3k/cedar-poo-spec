//! Typed mandate, offer, admission and shared-budget contracts for agentic AI commerce.

#[cfg(feature = "agentic-ai-commerce-admission")]
pub mod admission;
#[cfg(feature = "agentic-ai-commerce-budget-commit")]
pub mod budget_commit;
#[cfg(feature = "agentic-ai-commerce-credential")]
pub mod credential;
#[cfg(feature = "agentic-ai-commerce-projection")]
pub mod projection;
pub mod signatures;

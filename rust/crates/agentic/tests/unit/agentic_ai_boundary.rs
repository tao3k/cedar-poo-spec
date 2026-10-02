use super::{BoundaryFacts, SelectionDelta, SinkClass, ToolAction, admitted};

#[test]
fn selection_is_a_release_and_missing_observation_fails_closed() {
    let delta = SelectionDelta {
        before: ["p1", "p2", "p3"].map(str::to_owned).to_vec(),
        after: ["p1", "p2"].map(str::to_owned).to_vec(),
    };
    let candidates = delta.after.clone();
    let facts = BoundaryFacts {
        action: ToolAction::SelectionMutation,
        sink: SinkClass::SharedWorkspace,
        intended_selection: Some(&delta),
        observed_selection: Some(&delta),
        candidate_ids: &candidates,
        output_bound: true,
        audience_allowed: true,
        remote_model_approved: false,
    };
    assert!(admitted(&facts));
    assert!(!admitted(&BoundaryFacts {
        observed_selection: None,
        ..facts
    }));
    assert!(!admitted(&BoundaryFacts {
        action: ToolAction::ContentWrite,
        ..facts
    }));
    assert!(!admitted(&BoundaryFacts {
        sink: SinkClass::RemoteModel,
        ..facts
    }));
    assert!(
        !SelectionDelta {
            before: ["p1", "p2"].map(str::to_owned).to_vec(),
            after: ["p2", "p1"].map(str::to_owned).to_vec(),
        }
        .well_formed()
    );
}

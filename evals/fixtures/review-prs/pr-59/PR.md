# Fix `ValidationInfo.data` missing with `model_validate_json()`

## Change Summary

This PR fixes `ValidationInfo.data` missing when using `model_validate_json`. This is done by delaying validation of input JSON values until the JSON document has been full parsed; the validations can then be carried out in field order.

## Related issue number

Fixes #13074 

## Checklist

* [ ] The pull request title is a good summary of the changes - it will be used in the changelog
* [ ] Unit tests for the changes exist
* [ ] Tests pass on CI
* [ ] Documentation reflects the changes where applicable
* [ ] My PR is ready to review, **please add a comment including the phrase "please review" to assign reviewers**

# Contract Samples

Sample JSON documents conforming to HOSS validation contracts.

## Purpose

These samples serve as:
1. **Documentation** - Examples of valid request/result envelopes
2. **Testing** - Validation targets for schema correctness
3. **Reference** - Templates for integration testing

## Files

### Request Samples

- `validate.request.basic.json` - Minimal validation request
- `validate.request.strict.json` - Full request with strict mode and fab config

### Result Samples

- `validate.result.ok.json` - Successful validation envelope
- `validate.result.error.json` - Failed validation with error details

## Validation

Validate all samples against their schemas:

```bash
./scripts/validate-contracts.sh
```

## Schema References

- Request schema: `../validate.request.json`
- Result schema: `../validate.result.json`

## Usage in Testing

```bash
# Validate a sample against its schema
python3 -c "
import json
from jsonschema import validate

with open('app-pack/contracts/hoss/validate.request.json') as f:
    schema = json.load(f)

with open('app-pack/contracts/hoss/.samples/validate.request.basic.json') as f:
    sample = json.load(f)

validate(instance=sample, schema=schema)
print('✅ Valid')
"
```

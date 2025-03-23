# GitHub Actions Workflow for OATHTokens Module

This directory contains the GitHub Actions workflows for automating the OATHTokens module deployment to the PowerShell Gallery.

## Publish Workflow

The `publish.yml` workflow automates the process of publishing the PowerShell module to the PowerShell Gallery using a simple configuration approach.

### How it works

1. **Configuration File**: The workflow uses `/psgallery.json` to control publishing:
   - `version`: The version to publish
   - `publishThisVersion`: Boolean flag to control whether to publish
   - `releaseNotes`: Notes for the new release

2. **Triggers**:
   - The workflow is triggered on pushes to the `main` branch
   - Changes to the module files or the configuration file will trigger the workflow

3. **Version Management**:
   - The workflow will update the module manifest to match the version in the configuration file
   - This happens only when `publishThisVersion` is set to `true`

4. **Publishing Control**:
   - Set `publishThisVersion` to `true` to publish a new version
   - After successful publishing, the workflow automatically sets this flag back to `false`

### Required Secrets

For this workflow to function properly, you need to configure the following secret in your GitHub repository:

- `PSGALLERY_API_KEY`: Your PowerShell Gallery API key

## Setup Instructions

### 1. Create a PowerShell Gallery API Key

1. Log in to your [PowerShell Gallery account](https://www.powershellgallery.com/)
2. Go to your account settings
3. Generate a new API key with publishing rights
4. Copy the key (you won't be able to see it again)

### 2. Add the API Key to GitHub Secrets

1. Go to your GitHub repository
2. Navigate to Settings > Secrets and Variables > Actions
3. Click "New repository secret"
4. Name: `PSGALLERY_API_KEY`
5. Value: Paste your API key
6. Click "Add secret"

### 3. Publishing a New Version

To publish a new version to PowerShell Gallery:

1. Update the module code with your changes
2. Update `psgallery.json`:
   - Set `version` to the new version number
   - Set `publishThisVersion` to `true`
   - Update `releaseNotes` with information about the new version
3. Commit and push these changes to the main branch
4. The workflow will automatically:
   - Update the module manifest and PSM1 file with the new version
   - Publish to PowerShell Gallery
   - Set `publishThisVersion` back to `false`

## Troubleshooting

If the workflow fails, check:

1. **Secrets**: Ensure the `PSGALLERY_API_KEY` is properly configured
2. **Configuration File**: Verify the JSON file is valid and properly formatted
3. **Version Format**: Make sure versions follow the semantic versioning format (X.Y.Z)
4. **Workflow Logs**: Review the GitHub Actions logs for detailed error messages

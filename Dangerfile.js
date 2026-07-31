import { danger, warn, message, markdown } from 'danger';

// 1. Check for PR description
const pr = danger.github.pr;
if (!pr.body || pr.body.length < 20) {
  warn('Please add a detailed description to your PR to explain your changes.');
}

// 2. Warn if PR is Work In Progress (WIP)
const isWip = pr.title.includes('[WIP]') || pr.title.includes('wip:') || pr.draft;
if (isWip) {
  warn('This PR is marked as Work in Progress (WIP) and is not ready for merge.');
}

// 3. Check for lockfile updates when package.json changes
const webPackageChanged = danger.git.modified_files.includes('web/package.json');
const webLockChanged = danger.git.modified_files.includes('web/package-lock.json');

if (webPackageChanged && !webLockChanged) {
  warn('`web/package.json` was modified, but `web/package-lock.json` was not updated.');
}

// 4. Large PR warning
const totalChanges = danger.github.pr.additions + danger.github.pr.deletions;
if (totalChanges > 500) {
  warn(`This PR is large (+${danger.github.pr.additions} -${danger.github.pr.deletions} lines). Consider splitting it into smaller, manageable PRs.`);
}

// 5. Summary message
const modifiedCount = danger.git.modified_files.length;
const createdCount = danger.git.created_files.length;
const deletedCount = danger.git.deleted_files.length;

message(`PR Changes Summary: 📝 ${modifiedCount} modified, ➕ ${createdCount} created, ❌ ${deletedCount} deleted.`);

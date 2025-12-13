/**********************************************
 * Improved Test Workflow Orchestration Script
 *
 * This script triggers multiple GitHub Actions
 * workflows in batched parallel mode, waits
 * for each to complete, and moves on to the
 * next batch until all workflows finish.
 **********************************************/

// Parse full matrix collected by the YAML step
const ALL_WORKFLOWS = (process.env.WORKFLOWS_CSV || '')
  .split(',').map(s => s.trim()).filter(Boolean);

// Optional debug list: overrides everything when non-empty
const DEBUG_ONLY = [
];

// Final list to run
const WORKFLOWS = DEBUG_ONLY.length ? DEBUG_ONLY : ALL_WORKFLOWS;

if (!WORKFLOWS.length) {
  throw new Error('No workflows to run: check WORKFLOWS_CSV');
}

// Workflows in this list may fail without marking the whole matrix red
const EXPECTED_FAILURES = new Set([
  'share-link-oc-v10-nc-v27.yml',
  'share-link-oc-v10-nc-v28.yml',
  'share-link-oc-v10-nc-v29.yml',
  'share-link-oc-v10-nc-v30.yml',
  'share-link-oc-v10-nc-v31.yml',
  'share-link-oc-v10-nc-v32.yml',
]);

// full platform names for display
const PLATFORM_NAMES = {
  'crnbx': 'CERNBox',
  'nc sm': 'Nextcloud ScienceMesh',
  'nc': 'Nextcloud',
  'oc sm': 'ownCloud ScienceMesh',
  'oc': 'ownCloud',
  'ocis': 'oCIS',
  'opcl': 'OpenCloud',
  'os': 'OCM Stub',
  'sf': 'Seafile'
};

// Constants controlling polling / batching behavior
const POLL_INTERVAL_STATUS = 30000; // ms between each run status check
const POLL_INTERVAL_RUN_ID = 5000;  // ms between each new run ID check
const RUN_ID_TIMEOUT = 600000;       // ms to wait for a new run to appear
const INITIAL_RUN_ID_DELAY = 5000;  // ms initial wait before checking for run ID
const DEFAULT_BATCH_SIZE = 10;       // Workflows to run concurrently per batch

/**
 * Expand “crnbx v1” to “CERNBox v1”, “nc sm v27” to “Nextcloud ScienceMesh v27”.
 * Works for every sender/receiver label produced by `parseWorkflowName`.
 */
function prettyLabel(abbrev) {
  const parts = abbrev.split(' ');
  const plat = [];
  // everything up to the first v-token is the platform key
  while (parts.length && !/^v\d+/.test(parts[0])) plat.push(parts.shift());
  const platformKey = plat.join(' ');
  const platformFull = PLATFORM_NAMES[platformKey] || platformKey;
  return parts.length ? `${platformFull} ${parts.join(' ')}` : platformFull;
}

/**
 * Pause execution for the given number of milliseconds.
 * @param {number} ms - Milliseconds to sleep.
 * @returns {Promise<void>}
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wait until a given workflow run completes by polling its status.
 * @param {Object} github - GitHub API client.
 * @param {string} owner - Repository owner.
 * @param {string} repo - Repository name.
 * @param {number} runId - Workflow run ID.
 * @returns {Promise<string>} Conclusion of the workflow (e.g. 'success' or 'failure').
 */
async function waitForWorkflowCompletion(github, owner, repo, runId) {
  while (true) {
    try {
      const { data: run } = await github.rest.actions.getWorkflowRun({
        owner,
        repo,
        run_id: runId
      });

      if (run.status === 'completed') {
        return run.conclusion;
      }
    } catch (error) {
      console.error(`Error fetching run ${runId}: ${error.message}`);
    }
    await sleep(POLL_INTERVAL_STATUS);
  }
}

/**
 * Find the run ID of a newly triggered workflow by polling for an 'in_progress' run.
 * @param {Object} github - GitHub API client.
 * @param {Object} params - { owner, repo, workflow_id, branch } for the GitHub API.
 * @returns {Promise<number>} The detected run ID of the new workflow.
 * @throws If no new run is found within the timeout.
 */
async function findNewRunId(github, params) {
  await sleep(INITIAL_RUN_ID_DELAY);
  const startTime = Date.now();

  while (Date.now() - startTime < RUN_ID_TIMEOUT) {
    try {
      const { data: runs } = await github.rest.actions.listWorkflowRuns({
        ...params,
        status: 'in_progress',
        per_page: 1
      });

      if (runs.total_count > 0 && runs.workflow_runs.length > 0) {
        return runs.workflow_runs[0].id;
      }
    } catch (error) {
      console.error(`Error listing runs for workflow ${params.workflow_id}: ${error.message}`);
    }
    await sleep(POLL_INTERVAL_RUN_ID);
  }
  throw new Error(
    `Timeout: No in-progress run found for workflow ${params.workflow_id} within ${RUN_ID_TIMEOUT} ms`
  );
}

/**
 * Dispatch a workflow and retrieve the run ID once it's in progress.
 * @param {Object} github - GitHub API client.
 * @param {Object} context - GitHub Actions context (includes repo/owner/ref).
 * @param {string} workflow - Workflow file name to trigger.
 * @returns {Promise<{ name: string, runId: number }>} Name and runId of triggered workflow.
 */
async function triggerWorkflow(github, context, workflow) {
  console.log(`Triggering workflow: ${workflow}`);
  const { owner, repo } = context.repo;

  // Dispatch the workflow
  await github.rest.actions.createWorkflowDispatch({
    owner,
    repo,
    workflow_id: workflow,
    ref: context.ref
  });

  // Infer branch name from ref (e.g. 'refs/heads/main' -> 'main')
  const branch = context.ref.replace(/^refs\/heads\//, '');
  const runId = await findNewRunId(github, {
    owner,
    repo,
    workflow_id: workflow,
    branch
  });

  return { name: workflow, runId };
}

/**
 * Parse a workflow filename (without path) into its type, sender, receiver, and original name.
 * - login-nc-v27.yml { testType: 'login', senders: 'nc v27', receivers: 'nc v27' }
 * - share-with-nc-v28-os-v1.yml { testType: 'share-with', sender: 'nc v28', receiver: 'os v1' }
 * - invite-link-nc-sm-v27-nc-sm-v27.yml { testType: 'invite-link', sender: 'nc sm v27', receiver: 'nc sm v27' }
 * - invite-link-ocis-v7-oc-sm-v10.yml { testType: 'invite-link', sender: 'ocis v7', receiver: 'oc sm v10' }
 * - wayf-nc-v33-crnbx-v2.yml { testType: 'wayf', sender: 'nc v33', receiver: 'crnbx v2' }
 */
function parseWorkflowName(name) {
  const base = name.replace(/\.ya?ml$/, '');
  const parts = base.split('-');

  if (parts[0] === 'login') {
    const [, plat, ver] = parts;
    const label = `${plat} ${ver}`;
    return {
      testType: 'login',
      sender: label,
      receiver: label,
      name
    };
  } else if (parts[0] === 'wayf') {
    // wayf-nc-v33-crnbx-v2 pattern
    let i = 1;
    const senderTokens = [];
    const receiverTokens = [];

    // accumulate sender until we hit a "vNN" token
    while (i < parts.length && !/^v\d+/.test(parts[i])) {
      senderTokens.push(parts[i++]);
    }
    // include the version token itself
    if (i < parts.length && /^v\d+/.test(parts[i])) {
      senderTokens.push(parts[i++]);
    } else {
      throw new Error(`Cannot find sender version in ${name}`);
    }

    // now the rest is receiver, up through its version token
    while (i < parts.length && !/^v\d+/.test(parts[i])) {
      receiverTokens.push(parts[i++]);
    }
    if (i < parts.length && /^v\d+/.test(parts[i])) {
      receiverTokens.push(parts[i++]);
    } else {
      throw new Error(`Cannot find receiver version in ${name}`);
    }

    return {
      testType: 'wayf',
      sender: senderTokens.join(' '),
      receiver: receiverTokens.join(' '),
      name
    };
  } else {
    const testType = parts.slice(0, 2).join('-'); // e.g. 'share-with'
    // for others, parse sender then receiver by version‐marker
    let i = 2;
    const senderTokens = [];
    const receiverTokens = [];

    // accumulate sender until we hit a “vNN” token
    while (i < parts.length && !/^v\d+/.test(parts[i])) {
      senderTokens.push(parts[i++]);
    }
    // include the version token itself
    if (i < parts.length && /^v\d+/.test(parts[i])) {
      senderTokens.push(parts[i++]);
    } else {
      throw new Error(`Cannot find sender version in ${name}`);
    }

    // now the rest is receiver, up through its version token
    while (i < parts.length && !/^v\d+/.test(parts[i])) {
      receiverTokens.push(parts[i++]);
    }
    if (i < parts.length && /^v\d+/.test(parts[i])) {
      receiverTokens.push(parts[i++]);
    } else {
      throw new Error(`Cannot find receiver version in ${name}`);
    }

    return {
      testType,
      sender: senderTokens.join(' '),
      receiver: receiverTokens.join(' '),
      name
    };
  }
}

/**
 * Group parsed entries into { [testType]: { senders: Set, receivers: Set, entries: [] } }
 */
function groupResults(rawResults) {
  const groups = {};
  for (const r of rawResults) {
    const { testType, sender, receiver, name } = parseWorkflowName(r.name);
    if (!groups[testType]) {
      groups[testType] = {
        senders: new Set(),
        receivers: new Set(),
        entries: []
      };
    }
    const grp = groups[testType];
    // for login, parse returns sender/receiver as arrays
    if (Array.isArray(sender)) {
      grp.senders.add(...sender);
      grp.receivers.add(...receiver);
    } else {
      grp.senders.add(sender);
      grp.receivers.add(receiver);
    }
    grp.entries.push({ sender, receiver, name, runId: r.runId, conclusion: r.conclusion });
  }
  return groups;
}

/**
 * Main orchestration entry point.
* Batches workflows, triggers them in parallel, then waits for completion.
 * Moves on to the next batch until all workflows finish.
 *
 * @param {Object} github - GitHub API client.
 * @param {Object} context - GitHub Actions context.
 * @param {Object} core - actions/core object injected by github-script.
 */
module.exports = async function orchestrateTests(github, context, core) {
  const total = WORKFLOWS.length;
  const batchSize = DEFAULT_BATCH_SIZE;
  const totalBatches = Math.ceil(total / batchSize);
  // {name, runId, conclusion}
  const results = [];
  let processed = 0;
  let allSucceeded = true;
  // Run metadata for the summary 
  const RUN_URL = `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const COMMIT_URL = `https://github.com/${context.repo.owner}/${context.repo.repo}/tree/${context.sha}`;
  const TIMESTAMP = new Intl.DateTimeFormat('en-GB', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
    timeZoneName: 'short'
  }).format(new Date());

  console.log(`Orchestrating ${total} workflows in batches of ${batchSize}, ${totalBatches} batches to go …`);

  for (let i = 0; i < total; i += batchSize) {
    const batchNumber = Math.floor(i / batchSize) + 1;
    console.log(`\nProcessing batch ${batchNumber} of ${totalBatches} …`);
    const batch = WORKFLOWS.slice(i, i + batchSize);

    await Promise.all(batch.map(async wf => {
      try {
        const { name, runId } = await triggerWorkflow(github, context, wf);
        const concl = await waitForWorkflowCompletion(
          github, context.repo.owner, context.repo.repo, runId);
        results.push({ name, runId, conclusion: concl });
        if (concl !== 'success' && !EXPECTED_FAILURES.has(name)) {
          allSucceeded = false;
        }
      } catch (e) {
        results.push({ name: wf, runId: 0, conclusion: 'failure' });
        allSucceeded = false;
        console.error(e.message);
      }
      processed++;
      console.log(`${processed}/${total} done`);
    }));
  }

  const groups = groupResults(results);
  const totalCount = results.length;
  const passCount = results.filter(r =>
    r.conclusion === 'success' || EXPECTED_FAILURES.has(r.name)
  ).length;
  const failCount = totalCount - passCount;
  const passPct = Math.round((passCount / totalCount) * 100);

  await core.summary
    // Heading
    .addRaw('# OCM Compatibility Matrix 🔄\n\n')
    .addRaw(
      `<p><strong>Run&nbsp;time:</strong> <a href="${RUN_URL}">${TIMESTAMP}</a><br>` +
      `<strong>Commit:</strong> <a href="${COMMIT_URL}">${context.sha.slice(0, 7)}</a></p>\n\n`
    )

    // Overview
    .addRaw('## Overview\n')
    .addRaw('This matrix shows the compatibility status of **login**, **share-with**, **share-link**, **invite-link**, and **wayf** flows across all supported platform versions.\n'
      + 'Each cell is the outcome of an automated end-to-end test for a specific **sender to receiver** combination.\n\n')

    // Legend
    .addRaw('## Test Results Legend 🎯\n')
    .addRaw('- ✅ **Green** - all tests passed\n')
    .addRaw('- ⚠️ **Yellow** - expected/allowed failure\n')
    .addRaw('- ❌ **Red** - unexpected failure\n')
    .addRaw('- — **Gray** - test not executed for this pair\n\n')

    // High-level pass/fail counters
    .addRaw(`<p><strong>${passCount}/${totalCount}</strong> passed &nbsp;•&nbsp; <strong>${failCount}</strong> failed &nbsp;•&nbsp; <strong>${passPct}%</strong> success rate</p>`)

  for (const [testType, { senders, receivers, entries }] of Object.entries(groups)) {
    const typePass = entries.filter(e =>
      e.conclusion === 'success' || EXPECTED_FAILURES.has(e.name)
    ).length;
    const typeFail = entries.length - typePass;
    const typePct = Math.round((typePass / entries.length) * 100);

    // one collapsible section per test-type
    await core.summary.addRaw(
      `<details open>\n<summary><strong>${testType}</strong> - ${typePass}/${entries.length} passed&nbsp;(${typePct}%)</summary>\n\n`
    );

    // sort labels
    const senderList = [...senders].sort();
    const receiverList = [...receivers].sort();
    const totalCols = receiverList.length;

    // chunk receivers into blocks of 5
    for (let i = 0; i < totalCols; i += 5) {
      const chunk = receiverList.slice(i, i + 5);
      const colStart = i + 1;
      const colEnd = i + chunk.length;

      // caption (just the column range)
      await core.summary.addRaw(
        `<p><em>Columns ${colStart}-${colEnd} of ${totalCols}</em></p>`
      );

      // table header
      let html = `<table style="border-collapse: collapse; width: 100%;">\n  <thead>\n    <tr>` +
        `<th style="border: 1px solid #ddd; padding: 4px;">${testType === 'login' ? 'Platform' : 'Sender (Row) to Receiver (Column)'}</th>`;
      for (const rc of chunk) {
        html += `<th style="border: 1px solid #ddd; padding: 4px;">${prettyLabel(rc)}</th>`;
      }
      html += `</tr>\n  </thead>\n  <tbody>\n`;

      // rows
      const rows = testType === 'login' ? ['Result'] : senderList;
      for (const sd of rows) {
        html += `    <tr><td style="border: 1px solid #ddd; padding: 4px;">${prettyLabel(sd)}</td>`;
        for (const rc of chunk) {
          // find matching entry
          const cell = entries.find(e =>
          (testType === 'login'
            ? e.receiver === rc
            : e.sender === sd && e.receiver === rc)
          );
          if (cell) {
            const url = cell.runId
              ? `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${cell.runId}`
              : '';
            const isAllowed = EXPECTED_FAILURES.has(cell.name);
            const symbol = cell.conclusion === 'success'
              ? '✅'
              : isAllowed
                ? '⚠️'
                : '❌';
            const style = isAllowed
              ? 'background-color: yellow;'
              : '';

            html += `<td style="border: 1px solid #ddd; padding: 4px; ${style}">` +
              (url ? `<a href="${url}">${symbol}</a>` : symbol) +
              `</td>`;
          } else {
            html += `<td style="border: 1px solid #ddd; padding: 4px;">—</td>`;
          }
        }
        html += `</tr>\n`;
      }

      html += `  </tbody>\n</table>\n`;
      await core.summary.addRaw(html);
    }

    // close the collapsible block
    await core.summary.addRaw('\n</details>\n');
  }

  // final status
  await core.summary
    .addRaw(allSucceeded
      ? '🎉 **All groups succeeded!**'
      : '⚠️ **One or more failures detected.**');

  const fs = require('fs');
  const path = require('path');
  const matrixFile = path.join(process.cwd(), 'compatibility-matrix.md');

  // take a copy of the buffer before .write() clears it
  const snapshot = core.summary.stringify();

  // flush the buffer to the Actions “Step Summary” pane
  await core.summary.write(); // buffer is now empty

  // persist the snapshot for later jobs or artefacts
  fs.writeFileSync(matrixFile, snapshot, 'utf8');

  return matrixFile;
};

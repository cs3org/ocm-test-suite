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
  'login-nc-v27.yml',
  // 'login-nc-v28.yml',
  // 'login-nc-v29.yml',
  // 'login-nc-v30.yml',
  // 'login-nc-v31.yml',
  // 'login-nc-v32.yml',
  // 'login-ocis-v5.yml',
  // 'login-ocis-v7.yml',
  // 'login-oc-v10.yml',
  // 'login-os-v1.yml',
  // 'login-sf-v11.yml',
  // 'invite-link-nc-sm-v27-nc-sm-v27.yml',
  // 'invite-link-nc-sm-v27-ocis-v5.yml',
  // 'invite-link-nc-sm-v27-ocis-v7.yml',
  // 'invite-link-nc-sm-v27-oc-sm-v10.yml',
  // 'invite-link-ocis-v5-nc-sm-v27.yml',
  // 'invite-link-ocis-v5-ocis-v5.yml',
  // 'invite-link-ocis-v5-ocis-v7.yml',
  // 'invite-link-ocis-v5-oc-sm-v10.yml',
  // 'invite-link-ocis-v7-nc-sm-v27.yml',
  // 'invite-link-ocis-v7-ocis-v5.yml',
  // 'invite-link-ocis-v7-ocis-v7.yml',
  // 'invite-link-ocis-v7-oc-sm-v10.yml',
  // 'invite-link-oc-sm-v10-nc-sm-v27.yml',
  // 'invite-link-oc-sm-v10-ocis-v5.yml',
  // 'invite-link-oc-sm-v10-ocis-v7.yml',
  // 'invite-link-oc-sm-v10-oc-sm-v10.yml',
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

// Constants controlling polling / batching behavior
const POLL_INTERVAL_STATUS = 30000; // ms between each run status check
const POLL_INTERVAL_RUN_ID = 5000;  // ms between each new run ID check
const RUN_ID_TIMEOUT = 600000;       // ms to wait for a new run to appear
const INITIAL_RUN_ID_DELAY = 5000;  // ms initial wait before checking for run ID
const DEFAULT_BATCH_SIZE = 10;       // Workflows to run concurrently per batch

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

// utils/parseWorkflows.js
/**
 * Parse a workflow filename (without path) into its type, sender, receiver, and original name.
 * - login-nc-v27.yml { testType: 'login', senders: 'nc v27', receivers: 'nc v27' }
 * - share-with-nc-v28-os-v1.yml { testType: 'share-with', sender: 'nc v28', receiver: 'os v1' }
 * - invite-link-nc-sm-v27-nc-sm-v27.yml { testType: 'invite-link', sender: 'nc sm v27', receiver: 'nc sm v27' }
 * - invite-link-ocis-v7-oc-sm-v10.yml { testType: 'invite-link', sender: 'ocis v7', receiver: 'oc sm v10' }
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

  await core.summary.addHeading('🚀 OCM Test Suite Report: Matrix View');

  for (const [testType, { senders, receivers, entries }] of Object.entries(groups)) {
    // sort labels
    const senderList = [...senders].sort();
    const receiverList = [...receivers].sort();
    const totalCols = receiverList.length;

    // chunk receivers into blocks of 5
    for (let i = 0; i < totalCols; i += 5) {
      const chunk = receiverList.slice(i, i + 5);
      const colStart = i + 1;
      const colEnd = i + chunk.length;

      // caption
      await core.summary.addRaw(
        `<h4>${testType}</h4>` +
        `<p><em>Showing columns ${colStart}–${colEnd} of ${totalCols} receivers</em></p>`
      );

      // table header
      let html = `<table style="border-collapse: collapse; width: 100%;">\n  <thead>\n    <tr>` +
        `<th style="border: 1px solid #ddd; padding: 4px;">${testType === 'login' ? 'Result' : 'Sender to Receiver'}</th>`;
      for (const rc of chunk) {
        html += `<th style="border: 1px solid #ddd; padding: 4px;">${rc}</th>`;
      }
      html += `</tr>\n  </thead>\n  <tbody>\n`;

      // rows
      const rows = testType === 'login' ? ['Result'] : senderList;
      for (const sd of rows) {
        html += `    <tr><td style="border: 1px solid #ddd; padding: 4px;">${sd}</td>`;
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
  }

  // final status
  await core.summary
    .addRaw(allSucceeded
      ? '🎉 **All groups succeeded!**'
      : '⚠️ **One or more failures detected.**')
    .write();

  return results;
};

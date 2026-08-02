import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const baseUrl = (__ENV.BASE_URL || 'http://host.docker.internal:5066').replace(/\/$/, '');
const totalRequests = positiveInteger('TOTAL_REQUESTS', __ENV.TOTAL_REQUESTS || '1000');
const vus = positiveInteger('VUS', __ENV.VUS || '50');
const maxDuration = __ENV.MAX_DURATION || '30m';
const runId = sanitizeRunId(__ENV.RUN_ID || 'loadtest');
const password = __ENV.TEST_PASSWORD || 'LoadTest!12345';

const registrationsCreated = new Counter('registrations_created');
const registrationsRejected = new Counter('registrations_rejected');
const registrationSuccess = new Rate('registration_success');

export const options = {
  discardResponseBodies: true,
  scenarios: {
    registrations: {
      executor: 'shared-iterations',
      vus,
      iterations: totalRequests,
      maxDuration,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    registration_success: ['rate>0.99'],
    registrations_created: [`count==${totalRequests}`],
    http_req_duration: ['p(95)<2000'],
  },
};

export function setup() {
  console.log(`Registration load test: run=${runId}, requests=${totalRequests}, vus=${vus}, baseUrl=${baseUrl}`);
  return { runId };
}

export default function (data) {
  const iteration = exec.scenario.iterationInTest;
  const email = `load+${data.runId}-${iteration}@example.test`;
  const response = http.post(
    `${baseUrl}/api/auth/register`,
    JSON.stringify({ email, password }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags: { operation: 'register', run_id: data.runId },
      timeout: '60s',
    },
  );

  const created = check(response, {
    'registration returned 201': (result) => result.status === 201,
  });

  registrationSuccess.add(created);
  if (created) {
    registrationsCreated.add(1);
  } else {
    registrationsRejected.add(1);
  }
}

function positiveInteger(name, value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer; received '${value}'.`);
  }

  return parsed;
}

function sanitizeRunId(value) {
  const sanitized = value.toLowerCase().replace(/[^a-z0-9-]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
  if (!sanitized || sanitized.length > 48) {
    throw new Error('RUN_ID must contain letters, numbers, or hyphens and be at most 48 characters after sanitization.');
  }

  return sanitized;
}

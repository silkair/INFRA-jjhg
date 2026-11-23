// 진짜할게 API 가상 사용자 시나리오 (k6)
//
// 실행 (노트북, 저장소 폴더):
//   k6 run -e PROFILE=smoke  -e USER_MIN=.. -e USER_MAX=.. -e JWT_SECRET="$(grep ^JWT_SECRET= k8s/secret.env | cut -d= -f2-)" k6/scenario.js
//   PROFILE = smoke(1회 점검) | steady(배경 트래픽) | ramp(한계 측정) | measure(예열 2분 + 측정 4분, 비교용)
//
// 토큰은 앱과 같은 규칙(HS512, subject = user id)으로 여기서 만든다. JWT_SECRET은 명령에서만 넘기고 파일에 쓰지 않는다.

import http from 'k6/http';
import { check, sleep } from 'k6';
import crypto from 'k6/crypto';
import encoding from 'k6/encoding';

const BASE = __ENV.BASE_URL || 'http://jjhg.local';
const SECRET = __ENV.JWT_SECRET;
const USER_MIN = parseInt(__ENV.USER_MIN || '0');
const USER_MAX = parseInt(__ENV.USER_MAX || '0');
const PROFILE = __ENV.PROFILE || 'smoke';

const profiles = {
  // 시나리오 전체를 한 번 돌려 모든 API가 정상인지 본다
  smoke: { executor: 'shared-iterations', vus: 1, iterations: 1 },
  // 일정한 배경 트래픽. M6 장애 실험 동안 켜 둔다 (초당 2회 시나리오 ≈ 초당 약 9요청)
  steady: {
    executor: 'constant-arrival-rate',
    rate: parseInt(__ENV.RATE || '2'), timeUnit: '1s',
    duration: __ENV.DURATION || '10m',
    preAllocatedVUs: 20, maxVUs: 100,
  },
  // 2분마다 시나리오 횟수를 올려 어디서 느려지거나 실패하는지 찾는다
  ramp: {
    executor: 'ramping-arrival-rate',
    startRate: 2, timeUnit: '1s',
    preAllocatedVUs: 50, maxVUs: parseInt(__ENV.MAX_VUS || '400'),
    stages: [
      { target: 5, duration: '2m' },
      { target: 10, duration: '2m' },
      { target: 20, duration: '2m' },
      { target: 40, duration: '2m' },
      { target: parseInt(__ENV.PEAK || '60'), duration: '2m' },   // 처리량이 커지면 PEAK를 올려 끝까지 밀어 본다
      { target: 0, duration: '30s' },
    ],
  },
};

// measure: 비교 측정용. 앞 2분은 낮은 속도로 예열(JVM JIT·커넥션 준비), 뒤 4분만 측정 구간(main)으로 따로 집계한다
const measure = {
  warmup: {
    executor: 'constant-arrival-rate', rate: 5, timeUnit: '1s', duration: '2m',
    preAllocatedVUs: 10, maxVUs: 50,
  },
  main: {
    executor: 'constant-arrival-rate',
    rate: parseInt(__ENV.RATE || '30'), timeUnit: '1s',
    duration: __ENV.DURATION || '4m', startTime: '2m',
    preAllocatedVUs: 20, maxVUs: 100,
  },
};

export const options = {
  scenarios: PROFILE === 'measure' ? measure : { main: profiles[PROFILE] },
  thresholds: {
    http_req_failed: ['rate<0.01'],      // 실패 요청 1% 미만
    http_req_duration: ['p(95)<500'],    // p95 500ms 미만 (지금 알림 기준과 같음)
    checks: ['rate>0.99'],
    // 측정 구간(main)만 따로 요약에 나오게 한다
    'http_reqs{scenario:main}': ['count>=0'],
    'http_req_duration{scenario:main}': ['p(95)<500'],
    'dropped_iterations{scenario:main}': ['count>=0'],
  },
};

export function setup() {
  if (!SECRET || SECRET.length < 64) throw new Error('JWT_SECRET이 없거나 64자 미만');
  if (!USER_MIN || !USER_MAX || USER_MAX < USER_MIN) throw new Error('USER_MIN / USER_MAX 확인');
}

function token(userId) {
  const now = Math.floor(Date.now() / 1000);
  const h = encoding.b64encode(JSON.stringify({ alg: 'HS512' }), 'rawurl');
  const p = encoding.b64encode(JSON.stringify({ sub: String(userId), iat: now, exp: now + 1800 }), 'rawurl');
  const sig = crypto.hmac('sha512', SECRET, `${h}.${p}`, 'base64rawurl');
  return `${h}.${p}.${sig}`;
}

function isoDaysFromNow(days) {
  return new Date(Date.now() + days * 86400000).toISOString();
}

export default function () {
  // 가상 사용자마다 다른 사용자 id를 쓴다
  const userId = USER_MIN + ((__VU - 1) % (USER_MAX - USER_MIN + 1));
  const params = (name) => ({
    headers: { Authorization: `Bearer ${token(userId)}`, 'Content-Type': 'application/json' },
    tags: { name },   // 결과를 경로 이름으로 묶는다 (/api/contracts/123 → contracts_detail)
  });

  // 1. 내 정보
  let r = http.get(`${BASE}/api/users/me`, params('users_me'));
  check(r, { 'me 200': (x) => x.status === 200 });

  // 2. 내 계약 목록
  r = http.get(`${BASE}/api/contracts?role=CONTRACTOR&page=0&size=10`, params('contracts_list'));
  check(r, { 'list 200': (x) => x.status === 200 });

  // 3. 5번에 1번은 계약을 만들고 상세를 본다 (쓰기 요청)
  if (Math.random() < 0.2 || PROFILE === 'smoke') {
    const body = JSON.stringify({
      title: `부하테스트 ${userId}`,
      goal: '매일 30분 운동',
      reward: '치킨',
      totalProof: 3,
      oneOff: false,
      startDate: isoDaysFromNow(1),
      endDate: isoDaysFromNow(10),
      type: 'BASIC',
      signatureImageKey: 'loadtest/signature.png',
    });
    r = http.post(`${BASE}/api/contracts`, body, params('contracts_create'));
    const ok = check(r, { 'create 201': (x) => x.status === 201 });
    if (ok) {
      const id = r.json('result.contractId');
      r = http.get(`${BASE}/api/contracts/${id}`, params('contracts_detail'));
      check(r, { 'detail 200': (x) => x.status === 200 });
    }
  }

  // 4. 안 읽은 알림 수
  r = http.get(`${BASE}/api/notifications/unread`, params('notifications_unread'));
  check(r, { 'unread 200': (x) => x.status === 200 });

  if (PROFILE === 'smoke') sleep(0);
}

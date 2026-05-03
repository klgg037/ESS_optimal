function out = run_ess_gurobi()
% run_ess_gurobi
% ------------------------------------------------------------
% ESS 용량 및 운영 동시 최적화 MILP 모델
%
% 목적:
%   - ESS 에너지 용량 E_ESS [kWh] 최적화
%   - PCS 출력 P_PCS [kW] 최적화
%   - 시간별 충전/방전/계통구매전력 최적화
%   - 계약전력 forbid/penalty 모드 선택 가능
%   - PV 사용 여부 선택 가능
%   - infeasible 발생 시 IIS 진단 출력
%   - ESS 용량/PCS 출력이 상한값에 걸리는 경우 원인 진단 출력
%
% 필요:
%   - MATLAB
%   - Gurobi MATLAB interface
%
% 입력 CSV 기본 컬럼:
%   timestamp
%   load_kWh
%   pv_kWh                 optional
%   price_KRW_per_kWh       optional
%
% 주의:
%   1시간 kWh 데이터는 dt=1 h에서 평균전력 kW와 수치가 같지만,
%   코드에서는 load_kW = load_kWh / dt_h 로 명확히 처리한다.
% ------------------------------------------------------------

clc;

cfg = config_ess();

data = load_ess_data(cfg);

[model, idx, meta] = build_ess_model(cfg, data);

params = struct();
params.OutputFlag = cfg.gurobiOutputFlag;
params.MIPGap     = cfg.mipGap;
params.TimeLimit  = cfg.timeLimitSec;

if cfg.writeModelFile
    try
        gurobi_write(model, cfg.debugModelFile);
        fprintf('[INFO] Model file written: %s\n', cfg.debugModelFile);
    catch ME
        fprintf('[WARN] gurobi_write failed: %s\n', ME.message);
    end
end

out = struct();
out.cfg = cfg;
out.data = data;
out.model = model;
out.idx = idx;
out.meta = meta;

try
    result = gurobi(model, params);
catch ME
    fprintf('\n[ERROR] Gurobi 실행 중 오류 발생\n');
    fprintf('%s\n', ME.message);
    out.error = ME;
    return;
end

out.result = result;

fprintf('\n================ Gurobi Result ================\n');
fprintf('Status : %s\n', result.status);
if isfield(result, 'objval')
    fprintf('ObjVal : %.6f KRW/year-equivalent\n', result.objval);
end
if isfield(result, 'mipgap')
    fprintf('MIPGap : %.6g\n', result.mipgap);
end
if isfield(result, 'runtime')
    fprintf('Runtime: %.3f sec\n', result.runtime);
end

hasSolution = isfield(result, 'x');

if hasSolution && any(strcmp(result.status, {'OPTIMAL', 'SUBOPTIMAL', 'TIME_LIMIT'}))
    sol = extract_solution(result.x, idx, data, cfg);
    cost = compute_cost_breakdown(sol, data, cfg, meta);
    noess = compute_noess_baseline(data, cfg);

    out.sol = sol;
    out.cost = cost;
    out.noess = noess;

    report_solution(sol, cost, noess, cfg, data, meta);
    diagnose_upper_bound_solution(sol, cost, noess, cfg, data);

else
    fprintf('\n[WARN] 사용 가능한 해가 없습니다. Infeasible/Unbounded 가능성을 진단합니다.\n');

    if any(strcmp(result.status, {'INFEASIBLE', 'INF_OR_UNBD'}))
        diagnose_infeasible_model(model, meta, cfg);
    else
        fprintf('[INFO] 현재 status에서는 IIS 진단을 수행하지 않았습니다.\n');
    end
end

end

%% ============================================================
%  Configuration
% =============================================================
function cfg = config_ess()
% config_ess
% ------------------------------------------------------------
% 사용자가 논문 조건에 맞게 반드시 수정해야 하는 설정값 모음
% ------------------------------------------------------------

cfg = struct();

% ---------- 입력 파일 ----------
cfg.inputFile  = 'input_load.csv';
cfg.timeColumn = 'timestamp';
cfg.loadColumn = 'load_kWh';
cfg.pvColumn   = 'pv_kWh';
cfg.priceColumn = 'price_KRW_per_kWh';

% 입력 파일이 없을 때 예제 데이터를 생성할지 여부
% 논문 계산에서는 false 권장
cfg.allowSyntheticData = false;

% timestamp 형식
% 빈 값이면 MATLAB이 자동 추정
cfg.timeFormat = '';

% ---------- 시간 설정 ----------
cfg.dt_h = 1.0;
cfg.resampleToHourly = true;

% ---------- PV 옵션 ----------
cfg.usePV = false;

% ---------- 계약전력 옵션 ----------
% 'forbid'  : 계약전력 초과 불가
% 'penalty' : 계약전력 초과 허용, penalty 비용 부과
cfg.contractMode = 'forbid';

% 계약전력을 최적화 변수로 둘지 여부
% true  : P_contract 최적화
% false : contractFixed_kW로 고정
cfg.optimizeContract = true;

cfg.contractFixed_kW = 3000;
cfg.contractMin_kW   = 500;
cfg.contractMax_kW   = 8000;

% penalty 모드에서 사용하는 초과계약전력 비용
% 단위: 원/kW-year
% 실제 제도와 다를 수 있으므로 후속연구용 완화비용으로 해석
cfg.penaltyExceed_KRW_per_kW_year = 1.0e6;

% ---------- ESS/PCS 설비 범위 ----------
cfg.E_min_kWh = 0;
cfg.E_max_kWh = 20000;

cfg.P_min_kW = 0;
cfg.P_max_kW = 5000;

% ESS 지속시간 제약
cfg.enforceDuration = true;
cfg.durationMin_h = 1.0;
cfg.durationMax_h = 4.0;

% ---------- ESS 효율 및 SOC ----------
cfg.etaCharge = 0.95;
cfg.etaDischarge = 0.95;

cfg.socMin = 0.10;
cfg.socMax = 0.90;
cfg.socInitial = 0.50;

cfg.enforceTerminalSOC = true;

% ---------- 요금 ----------
% price_KRW_per_kWh 컬럼이 CSV에 없을 때 사용하는 기본 단가
% 논문 계산에서는 시간대별 단가 컬럼을 입력하는 것을 권장
cfg.defaultFlatEnergyPrice_KRW_per_kWh = 150;

% 기본요금 단가
% 논문에서는 반드시 최신 적용 단가로 교체
cfg.basicCharge_KRW_per_kW_month = 8000;

% ---------- 경제성 분석 ----------
cfg.projectYears = 15;
cfg.discountRate = 0.045;

% 투자비
% 논문에서는 견적, 문헌, 조달가격 등 근거 필요
cfg.capexESS_KRW_per_kWh = 450000;
cfg.capexPCS_KRW_per_kW  = 180000;

% 연간 유지보수비
cfg.omESS_KRW_per_kWh_year = 5000;
cfg.omPCS_KRW_per_kW_year  = 3000;

% 교체비
cfg.replacementESS_KRW_per_kWh = 300000;
cfg.replacementPCS_KRW_per_kW  = 100000;

% 수명
cfg.essReplacementLife_year = 10;
cfg.pcsReplacementLife_year = 15;

% ---------- Gurobi ----------
cfg.gurobiOutputFlag = 1;
cfg.mipGap = 1e-4;
cfg.timeLimitSec = 600;

% 모델 파일 저장
cfg.writeModelFile = true;
cfg.debugModelFile = 'debug_ess_model.lp';

end

%% ============================================================
%  Data loading
% =============================================================
function data = load_ess_data(cfg)
% load_ess_data
% ------------------------------------------------------------
% CSV 데이터를 읽고, 1시간 단위로 정리한다.
% load_kWh는 1시간 에너지이며, dt=1 h 기준 평균전력 kW로 변환한다.
% ------------------------------------------------------------

if ~isfile(cfg.inputFile)
    if cfg.allowSyntheticData
        fprintf('[WARN] 입력 파일이 없어 합성 데이터를 생성합니다.\n');
        data = create_synthetic_data(cfg);
        return;
    else
        error('입력 파일이 없습니다: %s', cfg.inputFile);
    end
end

Traw = readtable(cfg.inputFile);

required = {cfg.timeColumn, cfg.loadColumn};
for k = 1:numel(required)
    if ~ismember(required{k}, Traw.Properties.VariableNames)
        error('필수 컬럼 누락: %s', required{k});
    end
end

tsRaw = Traw.(cfg.timeColumn);

if ~isdatetime(tsRaw)
    if isempty(cfg.timeFormat)
        tsRaw = datetime(tsRaw);
    else
        tsRaw = datetime(tsRaw, 'InputFormat', cfg.timeFormat);
    end
end

loadRaw_kWh = Traw.(cfg.loadColumn);
loadRaw_kWh = loadRaw_kWh(:);

if any(isnan(loadRaw_kWh))
    error('load_kWh에 NaN이 포함되어 있습니다.');
end
if any(loadRaw_kWh < 0)
    error('load_kWh에 음수 값이 포함되어 있습니다.');
end

% PV 데이터
if cfg.usePV && ismember(cfg.pvColumn, Traw.Properties.VariableNames)
    pvRaw_kWh = Traw.(cfg.pvColumn);
    pvRaw_kWh = pvRaw_kWh(:);
    pvRaw_kWh(isnan(pvRaw_kWh)) = 0;
    if any(pvRaw_kWh < 0)
        error('pv_kWh에 음수 값이 포함되어 있습니다.');
    end
else
    pvRaw_kWh = zeros(size(loadRaw_kWh));
end

% 가격 데이터
hasPrice = ismember(cfg.priceColumn, Traw.Properties.VariableNames);
if hasPrice
    priceRaw = Traw.(cfg.priceColumn);
    priceRaw = priceRaw(:);
    if any(isnan(priceRaw))
        error('price_KRW_per_kWh에 NaN이 포함되어 있습니다.');
    end
else
    priceRaw = [];
end

% 시간 순서 정렬
[tsRaw, ord] = sort(tsRaw);
loadRaw_kWh = loadRaw_kWh(ord);
pvRaw_kWh   = pvRaw_kWh(ord);
if hasPrice
    priceRaw = priceRaw(ord);
end

% 1시간 리샘플링
if cfg.resampleToHourly
    tsHour = dateshift(tsRaw, 'start', 'hour');
    [grp, tsGroup] = findgroups(tsHour);

    loadHour_kWh = splitapply(@sum, loadRaw_kWh, grp);
    pvHour_kWh   = splitapply(@sum, pvRaw_kWh, grp);

    if hasPrice
        priceHour = splitapply(@mean, priceRaw, grp);
    else
        priceHour = cfg.defaultFlatEnergyPrice_KRW_per_kWh ...
                    * ones(size(loadHour_kWh));
    end

    [ts, ord2] = sort(tsGroup);
    loadHour_kWh = loadHour_kWh(ord2);
    pvHour_kWh   = pvHour_kWh(ord2);
    priceHour    = priceHour(ord2);
else
    ts = tsRaw;
    loadHour_kWh = loadRaw_kWh;
    pvHour_kWh   = pvRaw_kWh;

    if hasPrice
        priceHour = priceRaw;
    else
        priceHour = cfg.defaultFlatEnergyPrice_KRW_per_kWh ...
                    * ones(size(loadHour_kWh));
    end
end

% 1시간 kWh -> 평균 kW
load_kW = loadHour_kWh / cfg.dt_h;
pv_kW   = pvHour_kWh   / cfg.dt_h;

n = numel(ts);

if n < 2
    error('데이터 길이가 너무 짧습니다.');
end

data = struct();
data.ts = ts(:);
data.load_kWh = loadHour_kWh(:);
data.pv_kWh = pvHour_kWh(:);
data.load_kW = load_kW(:);
data.pv_kW = pv_kW(:);
data.price_KRW_per_kWh = priceHour(:);
data.dt_h = cfg.dt_h;
data.T = n;

% 연간 대표 스케일
% 8760시간 전체 데이터이면 1
data.yearScale = 8760 / n;

fprintf('\n================ Data Summary ================\n');
fprintf('Input file      : %s\n', cfg.inputFile);
fprintf('Number of hours : %d\n', n);
fprintf('Year scale      : %.6f\n', data.yearScale);
fprintf('Load min/mean/max [kW]: %.3f / %.3f / %.3f\n', ...
    min(data.load_kW), mean(data.load_kW), max(data.load_kW));
fprintf('Price min/mean/max [KRW/kWh]: %.3f / %.3f / %.3f\n', ...
    min(data.price_KRW_per_kWh), mean(data.price_KRW_per_kWh), max(data.price_KRW_per_kWh));

if cfg.usePV
    fprintf('PV min/mean/max [kW]: %.3f / %.3f / %.3f\n', ...
        min(data.pv_kW), mean(data.pv_kW), max(data.pv_kW));
end

end

function data = create_synthetic_data(cfg)
% create_synthetic_data
% ------------------------------------------------------------
% 코드 테스트용 합성 부하 데이터 생성
% 논문 결과에는 사용하지 말 것
% ------------------------------------------------------------

ts = (datetime(2025,1,1,0,0,0):hours(1):datetime(2025,12,31,23,0,0))';
n = numel(ts);

hourOfDay = hour(ts);
dayType = weekday(ts);
isWeekend = dayType == 1 | dayType == 7;

base = 1200;
daily = 500 * (hourOfDay >= 9 & hourOfDay <= 18);
weekendReduction = -250 * isWeekend;

season = month(ts);
summer = ismember(season, [6 7 8]);
winter = ismember(season, [12 1 2]);

seasonEffect = 400 * summer + 300 * winter;

rng(1);
noise = 80 * randn(n,1);

load_kW = max(300, base + daily + weekendReduction + seasonEffect + noise);
load_kWh = load_kW * cfg.dt_h;

pv_kW = zeros(n,1);
if cfg.usePV
    solarShape = max(0, sin((hourOfDay - 6) / 12 * pi));
    pv_kW = 800 * solarShape .* (~winter);
end
pv_kWh = pv_kW * cfg.dt_h;

price = cfg.defaultFlatEnergyPrice_KRW_per_kWh * ones(n,1);

data = struct();
data.ts = ts;
data.load_kWh = load_kWh;
data.pv_kWh = pv_kWh;
data.load_kW = load_kW;
data.pv_kW = pv_kW;
data.price_KRW_per_kWh = price;
data.dt_h = cfg.dt_h;
data.T = n;
data.yearScale = 8760 / n;

end

%% ============================================================
%  Model builder
% =============================================================
function [model, idx, meta] = build_ess_model(cfg, data)
% build_ess_model
% ------------------------------------------------------------
% Gurobi 행렬형 MILP 모델을 생성한다.
% ------------------------------------------------------------

T = data.T;
dt = data.dt_h;

% 연간 등가 투자비 계수 계산
[annCoef, annParts] = annualized_cost_coefficients(cfg);

% ---------- 변수 인덱스 생성 ----------
nvar = 0;
idx = struct();

nvar = nvar + 1;
idx.E = nvar;

nvar = nvar + 1;
idx.Ppcs = nvar;

nvar = nvar + 1;
idx.Pcon = nvar;

nvar = nvar + 1;
idx.Pexc = nvar;

idx.pGrid = (nvar+1):(nvar+T);
nvar = nvar + T;

idx.pCh = (nvar+1):(nvar+T);
nvar = nvar + T;

idx.pDis = (nvar+1):(nvar+T);
nvar = nvar + T;

idx.soc = (nvar+1):(nvar+T);
nvar = nvar + T;

idx.uCh = (nvar+1):(nvar+T);
nvar = nvar + T;

if cfg.usePV
    idx.pvUse = (nvar+1):(nvar+T);
    nvar = nvar + T;

    idx.pvCurt = (nvar+1):(nvar+T);
    nvar = nvar + T;
else
    idx.pvUse = [];
    idx.pvCurt = [];
end

% ---------- 변수 속성 ----------
lb = zeros(nvar,1);
ub = inf(nvar,1);
obj = zeros(nvar,1);
vtype = repmat('C', 1, nvar);
varnames = cell(nvar,1);

varnames{idx.E} = 'E_ESS_kWh';
varnames{idx.Ppcs} = 'P_PCS_kW';
varnames{idx.Pcon} = 'P_contract_kW';
varnames{idx.Pexc} = 'P_exceed_kW';

for t = 1:T
    varnames{idx.pGrid(t)} = sprintf('p_grid_kW_%04d', t);
    varnames{idx.pCh(t)}   = sprintf('p_ch_kW_%04d', t);
    varnames{idx.pDis(t)}  = sprintf('p_dis_kW_%04d', t);
    varnames{idx.soc(t)}   = sprintf('soc_kWh_%04d', t);
    varnames{idx.uCh(t)}   = sprintf('u_ch_%04d', t);
end

if cfg.usePV
    for t = 1:T
        varnames{idx.pvUse(t)}  = sprintf('p_pv_use_kW_%04d', t);
        varnames{idx.pvCurt(t)} = sprintf('p_pv_curt_kW_%04d', t);
    end
end

% 설비 변수 bound
lb(idx.E) = cfg.E_min_kWh;
ub(idx.E) = cfg.E_max_kWh;

lb(idx.Ppcs) = cfg.P_min_kW;
ub(idx.Ppcs) = cfg.P_max_kW;

% 계약전력 bound
if cfg.optimizeContract
    lb(idx.Pcon) = cfg.contractMin_kW;
    ub(idx.Pcon) = cfg.contractMax_kW;
else
    lb(idx.Pcon) = cfg.contractFixed_kW;
    ub(idx.Pcon) = cfg.contractFixed_kW;
end

% 계약전력 초과 변수
lb(idx.Pexc) = 0;
if strcmpi(cfg.contractMode, 'forbid')
    ub(idx.Pexc) = 0;
elseif strcmpi(cfg.contractMode, 'penalty')
    ub(idx.Pexc) = inf;
else
    error('cfg.contractMode는 forbid 또는 penalty이어야 합니다.');
end

% binary 변수
vtype(idx.uCh) = 'B';
lb(idx.uCh) = 0;
ub(idx.uCh) = 1;

% PV 변수 상한
if cfg.usePV
    for t = 1:T
        ub(idx.pvUse(t))  = max(0, data.pv_kW(t));
        ub(idx.pvCurt(t)) = max(0, data.pv_kW(t));
    end
end

% ---------- 목적함수 ----------
% 전력량요금
obj(idx.pGrid) = data.price_KRW_per_kWh(:) * dt * data.yearScale;

% 기본요금
obj(idx.Pcon) = 12 * cfg.basicCharge_KRW_per_kW_month;

% 계약초과 penalty
if strcmpi(cfg.contractMode, 'penalty')
    obj(idx.Pexc) = cfg.penaltyExceed_KRW_per_kW_year;
else
    obj(idx.Pexc) = 0;
end

% 연간등가 투자비 + 유지보수비 + 교체비
obj(idx.E)    = annCoef.E_total_KRW_per_kWh_year;
obj(idx.Ppcs) = annCoef.P_total_KRW_per_kW_year;

% ---------- 제약식 생성 ----------
Ai = [];
Aj = [];
Av = [];
rhs = [];
sense = '';
constrnames = {};
row = 0;

    function addrow(varIdx, coeff, senseChar, rhsVal, cname)
        row = row + 1;
        varIdx = varIdx(:);
        coeff = coeff(:);

        if numel(varIdx) ~= numel(coeff)
            error('addrow: 변수 인덱스와 계수 개수가 다릅니다.');
        end

        Ai = [Ai; repmat(row, numel(varIdx), 1)];
        Aj = [Aj; varIdx];
        Av = [Av; coeff];

        rhs(row,1) = rhsVal;
        sense(1,row) = senseChar;
        constrnames{row,1} = cname;
    end

% ---------- 시간별 제약 ----------
for t = 1:T

    % 전력수지
    % PV 미사용: p_grid - p_ch + p_dis = load
    % PV 사용  : p_grid - p_ch + p_dis + pv_use = load
    if cfg.usePV
        addrow( ...
            [idx.pGrid(t), idx.pCh(t), idx.pDis(t), idx.pvUse(t)], ...
            [1,            -1,         1,           1], ...
            '=', data.load_kW(t), ...
            sprintf('power_balance_%04d', t));

        % pv_use + pv_curt = pv_available
        addrow( ...
            [idx.pvUse(t), idx.pvCurt(t)], ...
            [1,            1], ...
            '=', data.pv_kW(t), ...
            sprintf('pv_balance_%04d', t));
    else
        addrow( ...
            [idx.pGrid(t), idx.pCh(t), idx.pDis(t)], ...
            [1,            -1,         1], ...
            '=', data.load_kW(t), ...
            sprintf('power_balance_%04d', t));
    end

    % 충전전력 <= PCS 출력
    addrow( ...
        [idx.pCh(t), idx.Ppcs], ...
        [1,          -1], ...
        '<', 0, ...
        sprintf('charge_le_pcs_%04d', t));

    % 방전전력 <= PCS 출력
    addrow( ...
        [idx.pDis(t), idx.Ppcs], ...
        [1,           -1], ...
        '<', 0, ...
        sprintf('discharge_le_pcs_%04d', t));

    % 충전 상태 binary 선형화
    % p_ch <= P_max * u_ch
    addrow( ...
        [idx.pCh(t), idx.uCh(t)], ...
        [1,          -cfg.P_max_kW], ...
        '<', 0, ...
        sprintf('charge_binary_%04d', t));

    % 방전 상태 binary 선형화
    % p_dis <= P_max * (1 - u_ch)
    % p_dis + P_max * u_ch <= P_max
    addrow( ...
        [idx.pDis(t), idx.uCh(t)], ...
        [1,           cfg.P_max_kW], ...
        '<', cfg.P_max_kW, ...
        sprintf('discharge_binary_%04d', t));

    % SOC 동역학
    if t == 1
        % soc(1) - socInitial*E - eta_ch*p_ch*dt + p_dis/eta_dis*dt = 0
        addrow( ...
            [idx.soc(t), idx.E, idx.pCh(t), idx.pDis(t)], ...
            [1,          -cfg.socInitial, -cfg.etaCharge*dt, dt/cfg.etaDischarge], ...
            '=', 0, ...
            sprintf('soc_dynamic_%04d', t));
    else
        % soc(t) - soc(t-1) - eta_ch*p_ch*dt + p_dis/eta_dis*dt = 0
        addrow( ...
            [idx.soc(t), idx.soc(t-1), idx.pCh(t), idx.pDis(t)], ...
            [1,          -1,           -cfg.etaCharge*dt, dt/cfg.etaDischarge], ...
            '=', 0, ...
            sprintf('soc_dynamic_%04d', t));
    end

    % SOC 상한: soc <= socMax * E
    % soc - socMax*E <= 0
    addrow( ...
        [idx.soc(t), idx.E], ...
        [1,          -cfg.socMax], ...
        '<', 0, ...
        sprintf('soc_upper_%04d', t));

    % SOC 하한: soc >= socMin * E
    % -soc + socMin*E <= 0
    addrow( ...
        [idx.soc(t), idx.E], ...
        [-1,         cfg.socMin], ...
        '<', 0, ...
        sprintf('soc_lower_%04d', t));

    % 계약전력 제약
    % p_grid <= P_contract + P_exceed
    % p_grid - P_contract - P_exceed <= 0
    addrow( ...
        [idx.pGrid(t), idx.Pcon, idx.Pexc], ...
        [1,            -1,       -1], ...
        '<', 0, ...
        sprintf('contract_limit_%04d', t));

end

% 최종 SOC 조건
if cfg.enforceTerminalSOC
    addrow( ...
        [idx.soc(T), idx.E], ...
        [1,          -cfg.socInitial], ...
        '=', 0, ...
        'terminal_soc');
end

% ESS 지속시간 제약
if cfg.enforceDuration
    % E >= durationMin * P
    % E - durationMin*P >= 0
    addrow( ...
        [idx.E, idx.Ppcs], ...
        [1,     -cfg.durationMin_h], ...
        '>', 0, ...
        'duration_min');

    % E <= durationMax * P
    % E - durationMax*P <= 0
    if isfinite(cfg.durationMax_h)
        addrow( ...
            [idx.E, idx.Ppcs], ...
            [1,     -cfg.durationMax_h], ...
            '<', 0, ...
            'duration_max');
    end
end

% ---------- Gurobi model struct ----------
model = struct();
model.A = sparse(Ai, Aj, Av, row, nvar);
model.obj = obj;
model.rhs = rhs;
model.sense = sense;
model.lb = lb;
model.ub = ub;
model.vtype = vtype;
model.modelsense = 'min';
model.modelname = 'ESS_capacity_operation_MILP';
model.varnames = varnames;
model.constrnames = constrnames;

% ---------- meta ----------
meta = struct();
meta.nvar = nvar;
meta.ncon = row;
meta.varnames = varnames;
meta.constrnames = constrnames;
meta.annCoef = annCoef;
meta.annParts = annParts;

fprintf('\n================ Model Summary ================\n');
fprintf('Variables   : %d\n', nvar);
fprintf('Constraints : %d\n', row);
fprintf('Binary vars : %d\n', numel(idx.uCh));
fprintf('PV enabled  : %d\n', cfg.usePV);
fprintf('Contract mode: %s\n', cfg.contractMode);

end

%% ============================================================
%  Cost coefficients
% =============================================================
function [annCoef, annParts] = annualized_cost_coefficients(cfg)
% annualized_cost_coefficients
% ------------------------------------------------------------
% 투자비, 유지보수비, 교체비를 연간 등가비용 계수로 변환한다.
% ------------------------------------------------------------

r = cfg.discountRate;
Y = cfg.projectYears;

if Y <= 0
    error('projectYears는 양수이어야 합니다.');
end

if abs(r) < 1e-12
    crf = 1 / Y;
else
    crf = r * (1+r)^Y / ((1+r)^Y - 1);
end

% 교체비의 현재가치
pvRepESS = replacement_present_value( ...
    cfg.replacementESS_KRW_per_kWh, ...
    cfg.essReplacementLife_year, ...
    Y, r);

pvRepPCS = replacement_present_value( ...
    cfg.replacementPCS_KRW_per_kW, ...
    cfg.pcsReplacementLife_year, ...
    Y, r);

annParts = struct();
annParts.crf = crf;

annParts.E_capex = cfg.capexESS_KRW_per_kWh * crf;
annParts.E_om    = cfg.omESS_KRW_per_kWh_year;
annParts.E_rep   = pvRepESS * crf;

annParts.P_capex = cfg.capexPCS_KRW_per_kW * crf;
annParts.P_om    = cfg.omPCS_KRW_per_kW_year;
annParts.P_rep   = pvRepPCS * crf;

annCoef = struct();
annCoef.E_total_KRW_per_kWh_year = ...
    annParts.E_capex + annParts.E_om + annParts.E_rep;

annCoef.P_total_KRW_per_kW_year = ...
    annParts.P_capex + annParts.P_om + annParts.P_rep;

end

function pv = replacement_present_value(unitCost, lifeYear, projectYears, discountRate)
% replacement_present_value
% ------------------------------------------------------------
% 분석기간 중 발생하는 교체비의 현재가치 합산
% 마지막 연도와 동일한 시점의 교체는 제외한다.
% ------------------------------------------------------------

pv = 0;

if lifeYear <= 0 || lifeYear >= projectYears
    return;
end

for y = lifeYear:lifeYear:(projectYears-1)
    pv = pv + unitCost / (1 + discountRate)^y;
end

end

%% ============================================================
%  Extract solution
% =============================================================
function sol = extract_solution(x, idx, data, cfg)
% extract_solution
% ------------------------------------------------------------
% Gurobi solution vector x를 해석 가능한 구조체로 변환한다.
% ------------------------------------------------------------

T = data.T;

sol = struct();
sol.E_ESS_kWh = x(idx.E);
sol.P_PCS_kW = x(idx.Ppcs);
sol.P_contract_kW = x(idx.Pcon);
sol.P_exceed_kW = x(idx.Pexc);

sol.p_grid_kW = x(idx.pGrid);
sol.p_ch_kW   = x(idx.pCh);
sol.p_dis_kW  = x(idx.pDis);
sol.soc_kWh   = x(idx.soc);
sol.u_ch      = x(idx.uCh);

if cfg.usePV
    sol.p_pv_use_kW  = x(idx.pvUse);
    sol.p_pv_curt_kW = x(idx.pvCurt);
else
    sol.p_pv_use_kW  = zeros(T,1);
    sol.p_pv_curt_kW = zeros(T,1);
end

sol.dispatchTable = table( ...
    data.ts, ...
    data.load_kW, ...
    data.pv_kW, ...
    data.price_KRW_per_kWh, ...
    sol.p_grid_kW, ...
    sol.p_ch_kW, ...
    sol.p_dis_kW, ...
    sol.soc_kWh, ...
    sol.u_ch, ...
    sol.p_pv_use_kW, ...
    sol.p_pv_curt_kW, ...
    'VariableNames', { ...
        'timestamp', ...
        'load_kW', ...
        'pv_kW', ...
        'price_KRW_per_kWh', ...
        'p_grid_kW', ...
        'p_ch_kW', ...
        'p_dis_kW', ...
        'soc_kWh', ...
        'u_ch', ...
        'p_pv_use_kW', ...
        'p_pv_curt_kW'});

end

%% ============================================================
%  Cost breakdown
% =============================================================
function cost = compute_cost_breakdown(sol, data, cfg, meta)
% compute_cost_breakdown
% ------------------------------------------------------------
% 목적함수 구성요소별 비용을 계산한다.
% ------------------------------------------------------------

dt = data.dt_h;
H = data.yearScale;

energyCost = H * sum(data.price_KRW_per_kWh .* sol.p_grid_kW * dt);

basicCost = 12 * cfg.basicCharge_KRW_per_kW_month * sol.P_contract_kW;

if strcmpi(cfg.contractMode, 'penalty')
    exceedCost = cfg.penaltyExceed_KRW_per_kW_year * sol.P_exceed_kW;
else
    exceedCost = 0;
end

essCapexAnnual = meta.annParts.E_capex * sol.E_ESS_kWh;
essOmAnnual    = meta.annParts.E_om    * sol.E_ESS_kWh;
essRepAnnual   = meta.annParts.E_rep   * sol.E_ESS_kWh;

pcsCapexAnnual = meta.annParts.P_capex * sol.P_PCS_kW;
pcsOmAnnual    = meta.annParts.P_om    * sol.P_PCS_kW;
pcsRepAnnual   = meta.annParts.P_rep   * sol.P_PCS_kW;

designCost = essCapexAnnual + essOmAnnual + essRepAnnual ...
           + pcsCapexAnnual + pcsOmAnnual + pcsRepAnnual;

totalCost = energyCost + basicCost + exceedCost + designCost;

cost = struct();
cost.energyCost = energyCost;
cost.basicCost = basicCost;
cost.exceedCost = exceedCost;

cost.essCapexAnnual = essCapexAnnual;
cost.essOmAnnual = essOmAnnual;
cost.essRepAnnual = essRepAnnual;

cost.pcsCapexAnnual = pcsCapexAnnual;
cost.pcsOmAnnual = pcsOmAnnual;
cost.pcsRepAnnual = pcsRepAnnual;

cost.designCost = designCost;
cost.totalCost = totalCost;

cost.table = table( ...
    energyCost, ...
    basicCost, ...
    exceedCost, ...
    essCapexAnnual, ...
    essOmAnnual, ...
    essRepAnnual, ...
    pcsCapexAnnual, ...
    pcsOmAnnual, ...
    pcsRepAnnual, ...
    designCost, ...
    totalCost);

end

%% ============================================================
%  No-ESS baseline
% =============================================================
function noess = compute_noess_baseline(data, cfg)
% compute_noess_baseline
% ------------------------------------------------------------
% ESS 미설치 기준 비용을 계산한다.
% PV 사용 시 PV는 부하 상쇄에만 사용하고 역송은 없다고 가정한다.
% ------------------------------------------------------------

dt = data.dt_h;
H = data.yearScale;

if cfg.usePV
    grid0 = max(data.load_kW - data.pv_kW, 0);
else
    grid0 = data.load_kW;
end

peak0 = max(grid0);

if cfg.optimizeContract
    Pcon0 = max(cfg.contractMin_kW, peak0);
    Pcon0 = min(Pcon0, cfg.contractMax_kW);
else
    Pcon0 = cfg.contractFixed_kW;
end

Pexc0 = max(0, peak0 - Pcon0);

energyCost0 = H * sum(data.price_KRW_per_kWh .* grid0 * dt);
basicCost0 = 12 * cfg.basicCharge_KRW_per_kW_month * Pcon0;

if strcmpi(cfg.contractMode, 'penalty')
    exceedCost0 = cfg.penaltyExceed_KRW_per_kW_year * Pexc0;
else
    exceedCost0 = 0;
end

noess = struct();
noess.grid_kW = grid0;
noess.peak_kW = peak0;
noess.P_contract_kW = Pcon0;
noess.P_exceed_kW = Pexc0;
noess.energyCost = energyCost0;
noess.basicCost = basicCost0;
noess.exceedCost = exceedCost0;
noess.operationCost = energyCost0 + basicCost0 + exceedCost0;

noess.feasibleUnderForbid = true;
if strcmpi(cfg.contractMode, 'forbid') && Pexc0 > 1e-6
    noess.feasibleUnderForbid = false;
end

end

%% ============================================================
%  Reports
% =============================================================
function report_solution(sol, cost, noess, cfg, data, meta)
% report_solution
% ------------------------------------------------------------
% 최적화 결과 요약 출력
% ------------------------------------------------------------

fprintf('\n================ Optimal Design ================\n');
fprintf('E_ESS       : %.6f kWh\n', sol.E_ESS_kWh);
fprintf('P_PCS       : %.6f kW\n', sol.P_PCS_kW);
fprintf('P_contract  : %.6f kW\n', sol.P_contract_kW);
fprintf('P_exceed    : %.6f kW\n', sol.P_exceed_kW);

fprintf('\n================ Cost Breakdown ================\n');
disp(cost.table);

fprintf('\n================ No-ESS Baseline ================\n');
fprintf('No-ESS peak grid       : %.6f kW\n', noess.peak_kW);
fprintf('No-ESS contract power  : %.6f kW\n', noess.P_contract_kW);
fprintf('No-ESS exceed power    : %.6f kW\n', noess.P_exceed_kW);
fprintf('No-ESS operation cost  : %.6f KRW/year\n', noess.operationCost);

if ~noess.feasibleUnderForbid
    fprintf('[WARN] No-ESS 기준은 forbid 조건에서 계약전력 초과가 발생합니다.\n');
end

optimizedOperationCost = cost.energyCost + cost.basicCost + cost.exceedCost;
operationSaving = noess.operationCost - optimizedOperationCost;
netSaving = noess.operationCost - cost.totalCost;

fprintf('\n================ Economic Comparison ================\n');
fprintf('Optimized operation cost, excluding ESS design cost : %.6f KRW/year\n', optimizedOperationCost);
fprintf('Operation saving before ESS design cost            : %.6f KRW/year\n', operationSaving);
fprintf('Net saving after annualized ESS design cost         : %.6f KRW/year\n', netSaving);

fprintf('\n================ Operation Summary ================\n');
fprintf('Grid peak after ESS       : %.6f kW\n', max(sol.p_grid_kW));
fprintf('Peak reduction            : %.6f kW\n', noess.peak_kW - max(sol.p_grid_kW));
fprintf('Total charge energy       : %.6f kWh/year-scaled\n', sum(sol.p_ch_kW * data.dt_h) * data.yearScale);
fprintf('Total discharge energy    : %.6f kWh/year-scaled\n', sum(sol.p_dis_kW * data.dt_h) * data.yearScale);

if sol.E_ESS_kWh > 1e-6
    equivCycles = sum(sol.p_dis_kW * data.dt_h) * data.yearScale / sol.E_ESS_kWh;
else
    equivCycles = 0;
end

fprintf('Equivalent full cycles    : %.6f cycles/year\n', equivCycles);

fprintf('\n================ Annualized Unit Cost ================\n');
fprintf('ESS annualized unit cost  : %.6f KRW/kWh-year\n', meta.annCoef.E_total_KRW_per_kWh_year);
fprintf('PCS annualized unit cost  : %.6f KRW/kW-year\n', meta.annCoef.P_total_KRW_per_kW_year);

end

%% ============================================================
%  Upper-bound diagnostics
% =============================================================
function diagnose_upper_bound_solution(sol, cost, noess, cfg, data)
% diagnose_upper_bound_solution
% ------------------------------------------------------------
% ESS 용량 또는 PCS 출력이 상한값으로 나오는 경우 원인 진단
% ------------------------------------------------------------

tolE = max(1e-5, 1e-6 * max(1, cfg.E_max_kWh));
tolP = max(1e-5, 1e-6 * max(1, cfg.P_max_kW));

hitE = sol.E_ESS_kWh >= cfg.E_max_kWh - tolE;
hitP = sol.P_PCS_kW >= cfg.P_max_kW - tolP;

fprintf('\n================ Bound Diagnostic ================\n');

if ~hitE && ~hitP
    fprintf('ESS 용량/PCS 출력 모두 상한에 걸리지 않았습니다.\n');
    return;
end

if hitE
    fprintf('[WARN] E_ESS가 상한값에 도달했습니다: %.6f / %.6f kWh\n', ...
        sol.E_ESS_kWh, cfg.E_max_kWh);
end

if hitP
    fprintf('[WARN] P_PCS가 상한값에 도달했습니다: %.6f / %.6f kW\n', ...
        sol.P_PCS_kW, cfg.P_max_kW);
end

% SOC 및 PCS 사용률 진단
socUpperHit = mean(abs(sol.soc_kWh - cfg.socMax * sol.E_ESS_kWh) <= 1e-4 * max(1, sol.E_ESS_kWh));
socLowerHit = mean(abs(sol.soc_kWh - cfg.socMin * sol.E_ESS_kWh) <= 1e-4 * max(1, sol.E_ESS_kWh));

pcsChargeHit = mean(abs(sol.p_ch_kW - sol.P_PCS_kW) <= 1e-4 * max(1, sol.P_PCS_kW));
pcsDisHit    = mean(abs(sol.p_dis_kW - sol.P_PCS_kW) <= 1e-4 * max(1, sol.P_PCS_kW));

fprintf('SOC upper hit ratio       : %.3f\n', socUpperHit);
fprintf('SOC lower hit ratio       : %.3f\n', socLowerHit);
fprintf('PCS charge binding ratio  : %.3f\n', pcsChargeHit);
fprintf('PCS discharge binding ratio: %.3f\n', pcsDisHit);

optimizedOperationCost = cost.energyCost + cost.basicCost + cost.exceedCost;
operationSaving = noess.operationCost - optimizedOperationCost;

fprintf('Operation saving before design cost: %.6f KRW/year\n', operationSaving);
fprintf('Annualized design cost             : %.6f KRW/year\n', cost.designCost);
fprintf('Net saving                         : %.6f KRW/year\n', noess.operationCost - cost.totalCost);

fprintf('\n[진단 해석]\n');

if operationSaving > cost.designCost
    fprintf('- 운영비 절감액이 설비 연간등가비용보다 큽니다. 상한값이 실제 경제적 최적보다 낮을 수 있습니다.\n');
else
    fprintf('- 운영비 절감액이 설비비보다 작거나 비슷합니다. 그런데도 상한에 걸렸다면 모델/단가/제약 오류 가능성이 큽니다.\n');
end

if sol.P_exceed_kW < 1e-6 && strcmpi(cfg.contractMode, 'forbid')
    fprintf('- forbid 조건에서 계약전력 초과가 완전히 차단되어 있습니다. 계약전력 하한이 낮으면 ESS가 과대 산정될 수 있습니다.\n');
end

if sol.P_contract_kW <= cfg.contractMin_kW + 1e-5
    fprintf('- 계약전력이 하한값에 붙었습니다. contractMin_kW가 비현실적으로 낮으면 ESS 용량이 과대 산정됩니다.\n');
end

if socUpperHit > 0.3 || socLowerHit > 0.3
    fprintf('- SOC 상한/하한에 자주 붙습니다. ESS 용량 제약이 운전 패턴을 강하게 제한하고 있습니다.\n');
end

if pcsChargeHit > 0.3 || pcsDisHit > 0.3
    fprintf('- PCS 출력 한계에 자주 붙습니다. P_PCS 상한 또는 C-rate 제약 민감도 분석이 필요합니다.\n');
end

fprintf('\n[필수 추가 실험]\n');
fprintf('1) E_max_kWh, P_max_kW를 1.5배, 2배로 증가시켜 상한 민감도 확인\n');
fprintf('2) capexESS, capexPCS를 ±30%% 변화시켜 경제성 민감도 확인\n');
fprintf('3) contractMin_kW를 변화시켜 계약전력 절감 효과 검증\n');
fprintf('4) terminal SOC 제약 제거/적용 비교\n');
fprintf('5) degradation 또는 cycle 비용 추가 후 결과 비교\n');

end

%% ============================================================
%  Infeasibility diagnostics
% =============================================================
function diagnose_infeasible_model(model, meta, cfg)
% diagnose_infeasible_model
% ------------------------------------------------------------
% Gurobi IIS를 이용해 infeasible 원인 후보를 출력한다.
% ------------------------------------------------------------

fprintf('\n================ Infeasibility Diagnostic ================\n');

try
    gurobi_write(model, 'infeasible_debug_model.lp');
    fprintf('[INFO] Infeasible debug model written: infeasible_debug_model.lp\n');
catch ME
    fprintf('[WARN] infeasible model write failed: %s\n', ME.message);
end

try
    params = struct();
    params.OutputFlag = 0;

    iis = gurobi_iis(model, params);

    fprintf('IIS minimal: %d\n', iis.minimal);

    if isfield(iis, 'Arows')
        rows = find(iis.Arows);
        fprintf('\n[IIS Constraints] count = %d\n', numel(rows));

        maxPrint = min(100, numel(rows));
        for k = 1:maxPrint
            r = rows(k);
            fprintf('  row %d : %s\n', r, meta.constrnames{r});
        end

        if numel(rows) > maxPrint
            fprintf('  ... %d more constraints omitted\n', numel(rows) - maxPrint);
        end
    end

    if isfield(iis, 'lb')
        lbVars = find(iis.lb);
        fprintf('\n[IIS Lower Bounds] count = %d\n', numel(lbVars));
        maxPrint = min(100, numel(lbVars));
        for k = 1:maxPrint
            v = lbVars(k);
            fprintf('  var %d : %s\n', v, meta.varnames{v});
        end
    end

    if isfield(iis, 'ub')
        ubVars = find(iis.ub);
        fprintf('\n[IIS Upper Bounds] count = %d\n', numel(ubVars));
        maxPrint = min(100, numel(ubVars));
        for k = 1:maxPrint
            v = ubVars(k);
            fprintf('  var %d : %s\n', v, meta.varnames{v});
        end
    end

    fprintf('\n[자주 발생하는 infeasible 원인]\n');
    fprintf('1) contractFixed_kW 또는 contractMax_kW가 너무 낮음\n');
    fprintf('2) forbid 모드에서 ESS/PV만으로 피크를 감당할 수 없음\n');
    fprintf('3) E_max_kWh 또는 P_max_kW가 너무 낮음\n');
    fprintf('4) durationMin_h, durationMax_h가 과도하게 빡빡함\n');
    fprintf('5) terminal SOC 조건과 데이터 마지막 구간 운전이 충돌\n');
    fprintf('6) PV 또는 load 데이터에 비정상 값 존재\n');

    fprintf('\n[현재 주요 설정]\n');
    fprintf('contractMode       : %s\n', cfg.contractMode);
    fprintf('optimizeContract   : %d\n', cfg.optimizeContract);
    fprintf('contractFixed_kW   : %.6f\n', cfg.contractFixed_kW);
    fprintf('contractMin_kW     : %.6f\n', cfg.contractMin_kW);
    fprintf('contractMax_kW     : %.6f\n', cfg.contractMax_kW);
    fprintf('E_max_kWh          : %.6f\n', cfg.E_max_kWh);
    fprintf('P_max_kW           : %.6f\n', cfg.P_max_kW);
    fprintf('durationMin_h      : %.6f\n', cfg.durationMin_h);
    fprintf('durationMax_h      : %.6f\n', cfg.durationMax_h);
    fprintf('terminalSOC        : %d\n', cfg.enforceTerminalSOC);

catch ME
    fprintf('[ERROR] IIS 계산 실패: %s\n', ME.message);
end

end
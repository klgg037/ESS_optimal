function outAll = run_ess_gurobi_paper_capex_sensitivity()
% run_ess_gurobi_paper_capex_sensitivity
% ------------------------------------------------------------
% 논문용 실제 부하데이터(PAPER)를 대상으로 ESS 투자비 민감도 분석을 순차 실행한다.
%
% 실행 Case
%   BASE  : ESS 배터리 투자비 100%
%   CASE1 : ESS 배터리 투자비  80%
%   CASE2 : ESS 배터리 투자비  60%
%   CASE3 : ESS 배터리 투자비  40%
%   CASE4 : ESS 배터리 투자비  20%
%
% 주의
%   - 각 case는 하나의 거대한 최적화 문제가 아니라 독립 최적화로 순차 실행된다.
%   - PCS 투자비는 기준값으로 유지한다. 즉, 본 파일은 ESS 배터리 kWh 단가 민감도 분석이다.
%   - 각 case 결과는 별도 폴더에 저장하여 파일 덮어쓰기와 결과 혼합을 방지한다.
%   - 실제 논문용 데이터는 시간이 오래 걸리므로, 먼저 BASE 또는 CASE1만 시험 실행하려면
%     caseLabels/capexScales 배열을 임시로 줄여서 실행한다.
% ------------------------------------------------------------

clc;
format long g;

% 기존 함수 캐시로 인한 구버전 실행을 방지하기 위한 안내 출력이다.
fprintf('\n[Capex Sensitivity] ESS 투자비 민감도 분석을 시작합니다.\n');
fprintf('[Capex Sensitivity] 실행 전 MATLAB 명령창에서 clear functions; rehash 수행을 권장합니다.\n');

% ---------- 민감도 Case 정의 및 선택 실행 설정 ----------
% 전체 case 정의
allCaseLabels  = {'BASE', 'CASE1', 'CASE2', 'CASE3', 'CASE4'};
allCapexScales = [1.00,   0.80,    0.60,    0.40,    0.20];

% -------------------------------------------------------------------------
% 실행할 case 선택
% -------------------------------------------------------------------------
% 현재 BASE, CASE1 결과가 이미 있으므로 기본값은 CASE2~CASE4만 실행한다.
% 전체 재실행: targetCases = {'BASE','CASE1','CASE2','CASE3','CASE4'};
% 특정 case만: targetCases = {'CASE2'};
% -------------------------------------------------------------------------
targetCases = {'CASE2','CASE3','CASE4'};

% -------------------------------------------------------------------------
% 실행할 scenario 선택
% -------------------------------------------------------------------------
% 전체 실행: targetScenarios = {'S0','S1','S2'};
% S2만 재실행: targetScenarios = {'S2'};
% -------------------------------------------------------------------------
targetScenarios = {'S0','S1','S2'};

% -------------------------------------------------------------------------
% S2 장시간 계산 대비 Gurobi 제한 설정
% -------------------------------------------------------------------------
% TIME_LIMIT으로 종료되어도 has_solution=true이면 제한시간 내 후보해로 검토 가능하다.
useSolverLimit = true;
solverTimeLimitSec = 14400;   % 1시간
solverMIPGap = 0.02;         % 2%

% 선택 case 필터링
caseMask = ismember(string(allCaseLabels), string(targetCases));
caseLabels  = allCaseLabels(caseMask);
capexScales = allCapexScales(caseMask);

if isempty(caseLabels)
    error('실행할 case가 없습니다. targetCases 설정을 확인하십시오.');
end

% S2만 재실행할 때는 기존 결과와 섞이지 않도록 폴더 접미사를 자동 부여한다.
if numel(targetScenarios) == 1 && strcmpi(string(targetScenarios{1}), "S2")
    outputScenarioSuffix = '_S2_RETRY';
    summaryRoot = 'results_PAPER_CAPEX_SENSITIVITY_SUMMARY_S2_RETRY';
else
    outputScenarioSuffix = '';
    summaryRoot = 'results_PAPER_CAPEX_SENSITIVITY_SUMMARY';
end

% 전체 민감도 결과 요약 저장 폴더
if ~exist(summaryRoot, 'dir')
    mkdir(summaryRoot);
end

fprintf('[Capex Sensitivity] Target cases     : %s\n', strjoin(targetCases, ', '));
fprintf('[Capex Sensitivity] Target scenarios : %s\n', strjoin(targetScenarios, ', '));
fprintf('[Capex Sensitivity] TimeLimit        : %.0f sec\n', solverTimeLimitSec);
fprintf('[Capex Sensitivity] MIPGap           : %.4f\n', solverMIPGap);

global ESS_CAPEX_SENSITIVITY_OVERRIDE;
outAll = struct();
outAll.caseLabels = caseLabels;
outAll.capexScales = capexScales;
outAll.caseResults = cell(numel(caseLabels), 1);
outAll.summaryRoot = summaryRoot;

comparisonAll = table();
npvAll = table();
annualNpvAll = table();
statusAll = table();
failedCases = table();

for k = 1:numel(caseLabels)
    label = caseLabels{k};
    scale = capexScales(k);
    tag = sprintf('%03d', round(scale * 100));

    fprintf('\n============================================================\n');
    fprintf('[%s] ESS 배터리 투자비 배율 = %.0f%%\n', label, scale * 100);
    fprintf('============================================================\n');

    % config_ess_revised() 내부에서 이 값을 읽어 PAPER/BASE/scale/outputDir를 설정한다.
    ESS_CAPEX_SENSITIVITY_OVERRIDE = struct();
    ESS_CAPEX_SENSITIVITY_OVERRIDE.inputDatasetMode = 'PAPER';
    ESS_CAPEX_SENSITIVITY_OVERRIDE.experimentCase   = 'CAPEX_SENSITIVITY';
    ESS_CAPEX_SENSITIVITY_OVERRIDE.capexESSScale    = scale;
    ESS_CAPEX_SENSITIVITY_OVERRIDE.capexCaseLabel    = label;
    ESS_CAPEX_SENSITIVITY_OVERRIDE.capexCaseTag      = tag;
    ESS_CAPEX_SENSITIVITY_OVERRIDE.outputDirSuffix   = ['_PAPER_CAPEX_', tag, '_', label, outputScenarioSuffix];

    % 선택 실행 및 solver 제한 설정을 config_ess_revised()에 전달한다.
    ESS_CAPEX_SENSITIVITY_OVERRIDE.targetScenarios = targetScenarios;
    ESS_CAPEX_SENSITIVITY_OVERRIDE.runOnlySelectedScenarios = true;
    if useSolverLimit
        ESS_CAPEX_SENSITIVITY_OVERRIDE.timeLimitSec = solverTimeLimitSec;
        ESS_CAPEX_SENSITIVITY_OVERRIDE.mipGap       = solverMIPGap;
    end

    try
        oneOut = run_capex_sensitivity_single_case_revised(label, scale, tag);
        outAll.caseResults{k} = oneOut;

        % ----- case별 comparison table 누적 -----
        T = oneOut.comparisonTable;
        T = add_case_columns_to_table_revised(T, label, scale, tag, oneOut.baseCfg.capexESS_KRW_per_kWh);
        comparisonAll = [comparisonAll; T]; %#ok<AGROW>

        % ----- case별 NPV table 누적 -----
        if isfield(oneOut, 'npvTable') && ~isempty(oneOut.npvTable)
            N = oneOut.npvTable;
            N = add_case_columns_to_table_revised(N, label, scale, tag, oneOut.baseCfg.capexESS_KRW_per_kWh);
            npvAll = [npvAll; N]; %#ok<AGROW>
        end

        % ----- case별 annual NPV table 누적 -----
        if isfield(oneOut, 'annualNpvTable') && ~isempty(oneOut.annualNpvTable)
            A = oneOut.annualNpvTable;
            A = add_case_columns_to_table_revised(A, label, scale, tag, oneOut.baseCfg.capexESS_KRW_per_kWh);
            annualNpvAll = [annualNpvAll; A]; %#ok<AGROW>
        end

        % ----- 시나리오별 status 누적 -----
        for s = 1:numel(oneOut.scenarios)
            sc = oneOut.scenarios{s};
            if isfield(sc, 'result')
                resultStatus = string(sc.result.status);
                resultObjVal = get_gurobi_field_safe_revised(sc.result, 'objval');
                resultObjBound = get_gurobi_field_safe_revised(sc.result, 'objbound');
                resultMipGap = get_gurobi_field_safe_revised(sc.result, 'mipgap');
                resultRuntime = get_gurobi_field_safe_revised(sc.result, 'runtime');
            else
                resultStatus = string(sc.status);
                resultObjVal = NaN;
                resultObjBound = NaN;
                resultMipGap = NaN;
                resultRuntime = NaN;
            end

            row = table(string(label), scale, string(tag), string(sc.cfg.scenarioId), string(sc.cfg.scenarioName), ...
                resultStatus, resultObjVal, resultObjBound, resultMipGap, resultRuntime, ...
                'VariableNames', {'case_label','capexESS_scale','case_tag','scenario_id','scenario_name', ...
                'status','objective_value','obj_bound','mip_gap','runtime_sec'});
            statusAll = [statusAll; row]; %#ok<AGROW>
        end

    catch ME
        warning('[%s] 실행 실패: %s', label, ME.message);
        failRow = table(string(label), scale, string(tag), string(ME.identifier), string(ME.message), ...
            'VariableNames', {'case_label','capexESS_scale','case_tag','error_id','error_message'});
        failedCases = [failedCases; failRow]; %#ok<AGROW>
    end

    % 다음 case에 override가 잘못 전파되지 않도록 초기화한다.
    ESS_CAPEX_SENSITIVITY_OVERRIDE = [];
end

% ---------- 전체 요약 파일 저장 ----------
outAll.comparisonAll = comparisonAll;
outAll.npvAll = npvAll;
outAll.annualNpvAll = annualNpvAll;
outAll.statusAll = statusAll;
outAll.failedCases = failedCases;

summaryComparisonCsv = fullfile(summaryRoot, 'capex_sensitivity_comparison_all.csv');
summaryNpvCsv        = fullfile(summaryRoot, 'capex_sensitivity_npv_all.csv');
summaryAnnualCsv     = fullfile(summaryRoot, 'capex_sensitivity_annual_npv_all.csv');
summaryStatusCsv     = fullfile(summaryRoot, 'capex_sensitivity_status_all.csv');
summaryFailCsv       = fullfile(summaryRoot, 'capex_sensitivity_failed_cases.csv');
summaryMat           = fullfile(summaryRoot, 'capex_sensitivity_all_results.mat');

if ~isempty(comparisonAll)
    writetable(comparisonAll, summaryComparisonCsv);
    try
        writetable(comparisonAll, fullfile(summaryRoot, 'capex_sensitivity_comparison_all.xlsx'));
    catch
    end
end
if ~isempty(npvAll)
    writetable(npvAll, summaryNpvCsv);
end
if ~isempty(annualNpvAll)
    writetable(annualNpvAll, summaryAnnualCsv);
end
if ~isempty(statusAll)
    writetable(statusAll, summaryStatusCsv);
end
if ~isempty(failedCases)
    writetable(failedCases, summaryFailCsv);
end
save(summaryMat, 'outAll', '-v7.3');

fprintf('\n============================================================\n');
fprintf('[완료] ESS 투자비 민감도 분석 종료\n');
fprintf('전체 요약 폴더: %s\n', summaryRoot);
if exist('summaryComparisonCsv', 'var')
    fprintf('전체 비교표 CSV: %s\n', summaryComparisonCsv);
end
fprintf('============================================================\n');

end

function oneOut = run_capex_sensitivity_single_case_revised(label, scale, tag)
% run_capex_sensitivity_single_case_revised
% ------------------------------------------------------------
% 하나의 ESS 투자비 민감도 case에 대해 S0/S1/S2를 순차 실행한다.
% ------------------------------------------------------------

baseCfg = config_ess_revised();

fprintf('\n[Case %s] inputFile = %s\n', label, baseCfg.inputFile);
fprintf('[Case %s] outputDir = %s\n', label, baseCfg.outputDir);
fprintf('[Case %s] capexESS = %.6g KRW/kWh, scale = %.2f\n', label, baseCfg.capexESS_KRW_per_kWh, scale);

% 실제 논문용 데이터 로드
data = load_ess_data_revised(baseCfg);

% 입력 데이터와 부하 증가율을 반영해 불필요하게 큰 설비/계약전력 상한을 자동 축소한다.
baseCfg = tighten_upper_bounds_from_data_revised(baseCfg, data);

% S0/S1에서 사용할 연도별 고정 계약전력을 입력 부하 데이터 기준으로 확정한다.
baseCfg = finalize_fixed_contract_by_year_revised(baseCfg, data);

scenarioCfgs = define_scenarios_A_revised(baseCfg);

% targetScenarios가 지정된 경우 선택된 시나리오만 남긴다.
% 이 필터는 실제 실행 루프 전에 적용되므로 S0/S1/S2 중 선택된 시나리오만 모델 생성 및 Gurobi 실행된다.
scenarioCfgs = filter_scenario_cfgs_by_target_revised(scenarioCfgs, baseCfg);

oneOut = struct();
oneOut.caseLabel = label;
oneOut.capexESSScale = scale;
oneOut.caseTag = tag;
oneOut.baseCfg = baseCfg;
oneOut.data = data;
oneOut.scenarioDefinition = build_scenario_definition_table_revised(scenarioCfgs);
oneOut.scenarios = cell(numel(scenarioCfgs), 1);

fprintf('\n================ Scenario Definition: %s ================\n', label);
disp(oneOut.scenarioDefinition);

for s = 1:numel(scenarioCfgs)
    cfg = scenarioCfgs{s};
    oneOut.scenarios{s} = run_single_ess_scenario_revised(cfg, data);
end

oneOut.comparisonTable = build_scenario_comparison_table_revised(oneOut.scenarios);
[oneOut.npvTable, oneOut.annualNpvTable] = build_scenario_npv_tables_revised(oneOut.scenarios);
oneOut.savedFiles = save_scenario_analysis_outputs_revised(oneOut, baseCfg);

fprintf('\n================ Scenario Cost Comparison: %s ================\n', label);
disp(oneOut.comparisonTable);

fprintf('\n================ Scenario NPV Comparison: %s ================\n', label);
disp(oneOut.npvTable);

end

function T = add_case_columns_to_table_revised(T, label, scale, tag, capexESS)
% add_case_columns_to_table_revised
% ------------------------------------------------------------
% table 앞쪽에 민감도 case 식별 열을 추가한다.
% ------------------------------------------------------------

n = height(T);
case_label = repmat(string(label), n, 1);
capexESS_scale = repmat(scale, n, 1);
case_tag = repmat(string(tag), n, 1);
capexESS_KRW_per_kWh = repmat(capexESS, n, 1);

T = addvars(T, case_label, capexESS_scale, case_tag, capexESS_KRW_per_kWh, 'Before', 1);

end

function v = get_gurobi_field_safe_revised(result, fieldName)
% get_gurobi_field_safe_revised
% ------------------------------------------------------------
% Gurobi 결과 struct에서 필드가 없을 때 NaN을 반환한다.
% ------------------------------------------------------------

if isfield(result, fieldName) && ~isempty(result.(fieldName))
    v = result.(fieldName);
else
    v = NaN;
end

end

%% ============================================================
%  Scenario runner
% =============================================================
function scenarioCfgs = define_scenarios_A_revised(baseCfg)
% define_scenarios_A_revised
% ------------------------------------------------------------
% A안 시나리오를 cfg 구조체 배열로 정의한다.
%
% S0: ESS 없음, 연도별 고정 계약전력
%     - P_contract_fix(y) = No-ESS 기준 연도별 최대부하로 외생 설정한다.
%     - 계약전력은 최적화하지 않지만, 부하 증가에 맞추어 매년 갱신된다.
%
% S1: ESS 있음, 연도별 고정 계약전력
%     - S0와 동일한 P_contract_fix(y)를 사용한다.
%     - ESS 단독 도입에 따른 전력량요금 절감 효과를 검토한다.
%
% S2: ESS 있음, 계약전력 최적화
%     - ESS/PCS 용량과 계약전력을 동시에 최적화한다.
% ------------------------------------------------------------

scenarioCfgs = cell(3,1);

cfg0 = baseCfg;
cfg0.scenarioId = 'S0';
cfg0.scenarioName = 'S0_NoESS_AnnualPeakContract';
cfg0.scenarioDescription = 'ESS 없음, 연도별 피크 기준 계약전력 시나리오';
cfg0.useESS = false;
cfg0.usePV = baseCfg.usePV;
cfg0.contractMode = 'forbid';
cfg0.optimizeContract = false;
cfg0.outputDir = fullfile(baseCfg.outputDir, cfg0.scenarioId);
cfg0.debugModelFile = fullfile(cfg0.outputDir, 'debug_S0_NoESS_AnnualPeakContract.lp');
scenarioCfgs{1} = cfg0;

cfg1 = baseCfg;
cfg1.scenarioId = 'S1';
cfg1.scenarioName = 'S1_ESS_AnnualPeakContract';
cfg1.scenarioDescription = 'ESS 있음, 연도별 피크 기준 계약전력 시나리오';
cfg1.useESS = true;
cfg1.usePV = baseCfg.usePV;
cfg1.contractMode = 'forbid';
cfg1.optimizeContract = false;
cfg1.outputDir = fullfile(baseCfg.outputDir, cfg1.scenarioId);
cfg1.debugModelFile = fullfile(cfg1.outputDir, 'debug_S1_ESS_AnnualPeakContract.lp');
scenarioCfgs{2} = cfg1;

cfg2 = baseCfg;
cfg2.scenarioId = 'S2';
cfg2.scenarioName = 'S2_ESS_OptimizedContract';
cfg2.scenarioDescription = 'ESS 있음, 계약전력 최적화 시나리오';
cfg2.useESS = true;
cfg2.usePV = baseCfg.usePV;
cfg2.contractMode = 'forbid';
cfg2.optimizeContract = true;
cfg2.outputDir = fullfile(baseCfg.outputDir, cfg2.scenarioId);
cfg2.debugModelFile = fullfile(cfg2.outputDir, 'debug_S2_ESS_OptimizedContract.lp');
scenarioCfgs{3} = cfg2;

end


function scenarioCfgsOut = filter_scenario_cfgs_by_target_revised(scenarioCfgsIn, baseCfg)
% filter_scenario_cfgs_by_target_revised
% ------------------------------------------------------------
% baseCfg.targetScenarios에 포함된 시나리오만 남긴다.
% 예:
%   baseCfg.targetScenarios = {'S2'};              -> S2만 실행
%   baseCfg.targetScenarios = {'S0','S1','S2'};    -> 전체 실행
% ------------------------------------------------------------

scenarioCfgsOut = scenarioCfgsIn;

if ~isfield(baseCfg, 'targetScenarios') || isempty(baseCfg.targetScenarios)
    return;
end

target = string(baseCfg.targetScenarios);
keep = false(numel(scenarioCfgsIn), 1);

for i = 1:numel(scenarioCfgsIn)
    sid = string(scenarioCfgsIn{i}.scenarioId);
    keep(i) = any(strcmpi(sid, target));
end

scenarioCfgsOut = scenarioCfgsIn(keep);

fprintf('\n[Scenario Filter] Target scenarios: %s\n', strjoin(cellstr(target), ', '));
fprintf('[Scenario Filter] Selected scenarios: ');
if isempty(scenarioCfgsOut)
    fprintf('NONE\n');
    error('선택된 시나리오가 없습니다. targetScenarios 설정을 확인하십시오.');
else
    for i = 1:numel(scenarioCfgsOut)
        fprintf('%s ', scenarioCfgsOut{i}.scenarioId);
    end
    fprintf('\n');
end

end


function defTable = build_scenario_definition_table_revised(scenarioCfgs)
% build_scenario_definition_table_revised
% ------------------------------------------------------------
% 시나리오 정의를 표로 정리한다.
% ------------------------------------------------------------

n = numel(scenarioCfgs);
scenario_id = strings(n,1);
scenario_name = strings(n,1);
description = strings(n,1);
use_ESS = false(n,1);
use_PV = false(n,1);
contract_mode = strings(n,1);
optimize_contract = false(n,1);
contract_fixed_mode = strings(n,1);
contract_fixed_y01_kW = zeros(n,1);
contract_fixed_yEnd_kW = zeros(n,1);
contract_fixed_min_kW = zeros(n,1);
contract_fixed_max_kW = zeros(n,1);
contract_min_kW = zeros(n,1);
contract_max_kW = zeros(n,1);
optimization_type = strings(n,1);
optimization_scope = strings(n,1);
replacement_model = strings(n,1);

for i = 1:n
    cfg = scenarioCfgs{i};
    scenario_id(i) = string(cfg.scenarioId);
    scenario_name(i) = string(cfg.scenarioName);
    description(i) = string(cfg.scenarioDescription);
    use_ESS(i) = cfg.useESS;
    use_PV(i) = cfg.usePV;
    contract_mode(i) = string(cfg.contractMode);
    optimize_contract(i) = cfg.optimizeContract;
    if isfield(cfg, 'contractFixedMode')
        contract_fixed_mode(i) = string(cfg.contractFixedMode);
    else
        contract_fixed_mode(i) = "single_value";
    end
    fixedVec = get_fixed_contract_by_year_revised(cfg, cfg.projectYears);
    contract_fixed_y01_kW(i) = fixedVec(1);
    contract_fixed_yEnd_kW(i) = fixedVec(end);
    contract_fixed_min_kW(i) = min(fixedVec);
    contract_fixed_max_kW(i) = max(fixedVec);
    contract_min_kW(i) = cfg.contractMin_kW;
    contract_max_kW(i) = cfg.contractMax_kW;
    optimization_type(i) = "multiyear_integrated_simultaneous_MILP";
    optimization_scope(i) = "all years solved in one MILP; annual design and hourly operation co-optimized";
    if cfg.useESS && cfg.includeESSDegradationBasedReplacement
        replacement_model(i) = "SOH 80% whole-ESS binary replacement";
    elseif cfg.useESS
        replacement_model(i) = "no replacement; degradation accumulated";
    else
        replacement_model(i) = "not applicable";
    end
end

defTable = table(scenario_id, scenario_name, description, use_ESS, use_PV, contract_mode, optimize_contract, ...
    optimization_type, optimization_scope, replacement_model, ...
    contract_fixed_mode, contract_fixed_y01_kW, contract_fixed_yEnd_kW, contract_fixed_min_kW, contract_fixed_max_kW, ...
    contract_min_kW, contract_max_kW);

end

function scenarioOut = run_single_ess_scenario_revised(cfg, data)
% run_single_ess_scenario_revised
% ------------------------------------------------------------
% 단일 시나리오에 대해 모델 생성, Gurobi 실행, 결과 추출, 저장을 수행한다.
% ------------------------------------------------------------

fprintf('\n============================================================\n');
fprintf('Scenario %s : %s\n', cfg.scenarioId, cfg.scenarioDescription);
fprintf('============================================================\n');

if cfg.saveResults && ~exist(cfg.outputDir, 'dir')
    mkdir(cfg.outputDir);
end

[model, idx, meta] = build_ess_model_revised(cfg, data);
model.modelname = ['ESS_', cfg.scenarioName];

params = struct();
params.OutputFlag = cfg.gurobiOutputFlag;
params.MIPGap     = cfg.mipGap;
params.TimeLimit  = cfg.timeLimitSec;

% Gurobi 성능 및 수치 안정성 설정
% 핵심 병목은 시간별 u_ch binary이므로, 기본 설정에서는 u_ch를 제거한다.
% 아래 파라미터는 남아 있는 소수의 integer/binary 변수와 큰 LP를 안정적으로 풀기 위한 보조 설정이다.
if isfield(cfg, 'gurobiPresolve'),      params.Presolve      = cfg.gurobiPresolve;      end
if isfield(cfg, 'gurobiCuts'),          params.Cuts          = cfg.gurobiCuts;          end
if isfield(cfg, 'gurobiMIPFocus'),      params.MIPFocus      = cfg.gurobiMIPFocus;      end
if isfield(cfg, 'gurobiThreads'),       params.Threads       = cfg.gurobiThreads;       end
if isfield(cfg, 'gurobiNumericFocus'),  params.NumericFocus  = cfg.gurobiNumericFocus;  end
if isfield(cfg, 'gurobiNodefileStart'), params.NodefileStart = cfg.gurobiNodefileStart; end
if isfield(cfg, 'gurobiNodefileDir') && ~isempty(cfg.gurobiNodefileDir)
    if ~exist(cfg.gurobiNodefileDir, 'dir')
        mkdir(cfg.gurobiNodefileDir);
    end
    params.NodefileDir = cfg.gurobiNodefileDir;
end

scenarioOut = struct();
scenarioOut.cfg = cfg;
scenarioOut.data = data;
scenarioOut.model = model;
scenarioOut.idx = idx;
scenarioOut.meta = meta;
scenarioOut.status = 'NOT_SOLVED';
scenarioOut.errorMessage = '';

if cfg.writeModelFile
    try
        gurobi_write(model, cfg.debugModelFile);
        fprintf('[INFO] Model file written: %s\n', cfg.debugModelFile);
    catch ME
        fprintf('[WARN] gurobi_write failed: %s\n', ME.message);
    end
end

try
    result = gurobi(model, params);
catch ME
    fprintf('\n[ERROR] Gurobi 실행 중 오류 발생: %s\n', ME.message);
    scenarioOut.error = ME;
    scenarioOut.errorMessage = ME.message;
    scenarioOut.status = 'GUROBI_ERROR';
    scenarioOut.statusFile = save_scenario_status_revised(scenarioOut, cfg);
    return;
end

scenarioOut.result = result;
scenarioOut.status = result.status;

fprintf('\n================ Gurobi Result: %s ================\n', cfg.scenarioId);
fprintf('Status : %s\n', result.status);
if isfield(result, 'objval')
    fprintf('ObjVal : %s\n', fmt_krw(result.objval));
end
if isfield(result, 'mipgap')
    fprintf('MIPGap : %s\n', fmt_real(result.mipgap, 8));
end
if isfield(result, 'runtime')
    fprintf('Runtime: %.3f sec\n', result.runtime);
end

hasSolution = isfield(result, 'x');

if hasSolution && any(strcmp(result.status, {'OPTIMAL', 'SUBOPTIMAL', 'TIME_LIMIT'}))
    sol = extract_solution_revised(result.x, idx, data, cfg, meta);
    cost = compute_cost_breakdown_revised(sol, data, cfg, meta);
    noess = compute_noess_baseline_revised(data, cfg, meta);

    scenarioOut.sol = sol;
    scenarioOut.cost = cost;
    scenarioOut.noess = noess;

    report_solution_revised(sol, cost, noess, cfg, data, meta);
    diagnose_upper_bound_solution_revised(sol, cost, noess, cfg, data);
    scenarioOut.savedFiles = save_outputs_revised(scenarioOut, cfg);
else
    fprintf('\n[WARN] 사용 가능한 해가 없습니다. Infeasible/Unbounded 가능성을 진단합니다.\n');

    if any(strcmp(result.status, {'INFEASIBLE', 'INF_OR_UNBD'}))
        diagnose_infeasible_model_revised(model, meta, cfg);
    else
        fprintf('[INFO] 현재 status에서는 IIS 진단을 수행하지 않았습니다.\n');
    end
end

scenarioOut.statusFile = save_scenario_status_revised(scenarioOut, cfg);

end

function statusFile = save_scenario_status_revised(scenarioOut, cfg)
% save_scenario_status_revised
% ------------------------------------------------------------
% 해가 있든 없든 시나리오별 실행 상태를 자동 저장한다.
% Infeasible/오류 시에도 status 파일이 남도록 하기 위한 함수이다.
% ------------------------------------------------------------

statusFile = '';
if ~cfg.saveResults
    return;
end
if ~exist(cfg.outputDir, 'dir')
    mkdir(cfg.outputDir);
end

scenario_id = string(cfg.scenarioId);
scenario_name = string(cfg.scenarioName);
status = string(scenarioOut.status);
error_message = string(scenarioOut.errorMessage);
optimization_type = "multiyear_integrated_simultaneous_MILP";
optimization_definition = "One MILP over all years; ESS capacity, PCS capacity, contract demand, replacement, annual expansion, and hourly operation are co-optimized.";
use_ESS = cfg.useESS;
optimize_contract = cfg.optimizeContract;
contract_mode = string(cfg.contractMode);
project_years = cfg.projectYears;
load_growth_rate = cfg.loadGrowthRate;
replacement_trigger_SOH = cfg.replacementAtSOH;
replacement_trigger_loss_fraction = cfg.replacementTriggerLossFraction;
objective_value_KRW = NaN;
runtime_sec = NaN;
mipgap = NaN;
has_solution = false;

if isfield(scenarioOut, 'result')
    if isfield(scenarioOut.result, 'objval')
        objective_value_KRW = scenarioOut.result.objval;
    end
    if isfield(scenarioOut.result, 'runtime')
        runtime_sec = scenarioOut.result.runtime;
    end
    if isfield(scenarioOut.result, 'mipgap')
        mipgap = scenarioOut.result.mipgap;
    end
    has_solution = isfield(scenarioOut.result, 'x');
end

statusTable = table(scenario_id, scenario_name, status, error_message, optimization_type, optimization_definition, ...
    use_ESS, optimize_contract, contract_mode, project_years, load_growth_rate, replacement_trigger_SOH, ...
    replacement_trigger_loss_fraction, objective_value_KRW, runtime_sec, mipgap, has_solution);

statusFile = fullfile(cfg.outputDir, sprintf('scenario_%s_status.csv', char(scenario_id)));
writetable(statusTable, statusFile);

end

function comparisonTable = build_scenario_comparison_table_revised(scenarioResults)
% build_scenario_comparison_table_revised
% ------------------------------------------------------------
% 시나리오별 비용, 설비용량, 계약전력, 피크저감 효과를 하나의 표로 정리한다.
% ------------------------------------------------------------

n = numel(scenarioResults);
scenario_id = strings(n,1);
scenario_name = strings(n,1);
description = strings(n,1);
status = strings(n,1);
use_ESS = false(n,1);
optimize_contract = false(n,1);
contract_mode = strings(n,1);

objective_value_KRW = nan(n,1);
total_PV_cost_KRW = nan(n,1);
operation_cost_PV_KRW = nan(n,1);
design_cost_PV_KRW = nan(n,1);
energy_cost_PV_KRW = nan(n,1);
basic_cost_PV_KRW = nan(n,1);
exceed_cost_PV_KRW = nan(n,1);
ess_capex_PV_KRW = nan(n,1);
pcs_capex_PV_KRW = nan(n,1);
om_cost_PV_KRW = nan(n,1);
replacement_cost_PV_KRW = nan(n,1);
facility_expansion_cost_PV_KRW = nan(n,1);
stabilization_penalty_PV_KRW = nan(n,1);

final_E_ESS_kWh = nan(n,1);
final_E_usable_kWh = nan(n,1);
final_P_PCS_kW = nan(n,1);
final_P_contract_kW = nan(n,1);
final_P_grid_max_kW = nan(n,1);
final_peak_reduction_kW = nan(n,1);
total_E_replacement_kWh = nan(n,1);

for i = 1:n
    r = scenarioResults{i};
    cfg = r.cfg;
    scenario_id(i) = string(cfg.scenarioId);
    scenario_name(i) = string(cfg.scenarioName);
    description(i) = string(cfg.scenarioDescription);
    status(i) = string(r.status);
    use_ESS(i) = cfg.useESS;
    optimize_contract(i) = cfg.optimizeContract;
    contract_mode(i) = string(cfg.contractMode);

    if isfield(r, 'result') && isfield(r.result, 'objval')
        objective_value_KRW(i) = r.result.objval;
    end

    if isfield(r, 'cost')
        total_PV_cost_KRW(i) = r.cost.totalPresentValue;
        operation_cost_PV_KRW(i) = r.cost.operationCostPV;
        design_cost_PV_KRW(i) = r.cost.designCostPV;
        energy_cost_PV_KRW(i) = r.cost.energyCostPV;
        basic_cost_PV_KRW(i) = r.cost.basicCostPV;
        exceed_cost_PV_KRW(i) = r.cost.exceedCostPV;
        ess_capex_PV_KRW(i) = r.cost.essCapexPV;
        pcs_capex_PV_KRW(i) = r.cost.pcsCapexPV;
        om_cost_PV_KRW(i) = r.cost.omCostPV;
        replacement_cost_PV_KRW(i) = r.cost.replacementCostPV;
        facility_expansion_cost_PV_KRW(i) = r.cost.facilityExpansionCostPV;
        if isfield(r.cost, 'stabilizationPenaltyPV')
            stabilization_penalty_PV_KRW(i) = r.cost.stabilizationPenaltyPV;
        end
    end

    if isfield(r, 'sol')
        final_E_ESS_kWh(i) = r.sol.E_ESS_kWh(end);
        final_E_usable_kWh(i) = r.sol.E_usable_kWh(end);
        final_P_PCS_kW(i) = r.sol.P_PCS_kW(end);
        final_P_contract_kW(i) = r.sol.P_contract_kW(end);
        final_P_grid_max_kW(i) = r.sol.annualTable.P_grid_max_kW(end);
        final_peak_reduction_kW(i) = r.sol.annualTable.peak_reduction_kW(end);
        total_E_replacement_kWh(i) = sum(r.sol.E_replacement_kWh);
    end
end

baselineCost = total_PV_cost_KRW(1);
if isnan(baselineCost)
    saving_vs_S0_KRW = nan(n,1);
    saving_rate_vs_S0_percent = nan(n,1);
else
    saving_vs_S0_KRW = baselineCost - total_PV_cost_KRW;
    saving_rate_vs_S0_percent = 100 * saving_vs_S0_KRW / baselineCost;
end

% NPV 정의:
%   S0를 기준안으로 두고, 각 시나리오의 총비용 현재가치가 S0보다 얼마나 감소하는지 계산한다.
%   NPV_vs_S0 = PV(total cost of S0) - PV(total cost of scenario)
%   따라서 양수이면 S0 대비 경제성이 있고, 음수이면 S0보다 불리하다.
NPV_vs_S0_KRW = saving_vs_S0_KRW;
NPV_rate_vs_S0_percent = saving_rate_vs_S0_percent;
NPV_judgement = strings(n,1);
for k = 1:n
    if isnan(NPV_vs_S0_KRW(k))
        NPV_judgement(k) = "NOT_AVAILABLE";
    elseif k == 1
        NPV_judgement(k) = "BASELINE";
    elseif ~strcmpi(char(status(k)), 'OPTIMAL')
        NPV_judgement(k) = "NOT_PROVEN_" + status(k);
    elseif NPV_vs_S0_KRW(k) > 0
        NPV_judgement(k) = "ECONOMIC_vs_S0";
    elseif abs(NPV_vs_S0_KRW(k)) <= 1e-6
        NPV_judgement(k) = "BREAKEVEN_vs_S0";
    else
        NPV_judgement(k) = "NOT_ECONOMIC_vs_S0";
    end
end

comparisonTable = table( ...
    scenario_id, scenario_name, description, status, use_ESS, optimize_contract, contract_mode, ...
    objective_value_KRW, total_PV_cost_KRW, saving_vs_S0_KRW, saving_rate_vs_S0_percent, ...
    NPV_vs_S0_KRW, NPV_rate_vs_S0_percent, NPV_judgement, ...
    operation_cost_PV_KRW, design_cost_PV_KRW, energy_cost_PV_KRW, basic_cost_PV_KRW, exceed_cost_PV_KRW, ...
    ess_capex_PV_KRW, pcs_capex_PV_KRW, om_cost_PV_KRW, replacement_cost_PV_KRW, facility_expansion_cost_PV_KRW, stabilization_penalty_PV_KRW, ...
    final_E_ESS_kWh, final_E_usable_kWh, final_P_PCS_kW, final_P_contract_kW, final_P_grid_max_kW, final_peak_reduction_kW, total_E_replacement_kWh);

end


function [npvTable, annualNpvTable] = build_scenario_npv_tables_revised(scenarioResults)
% build_scenario_npv_tables_revised
% ------------------------------------------------------------
% S0를 기준안으로 두고 각 시나리오의 NPV를 계산한다.
%
% 본 코드의 NPV 정의:
%   NPV_vs_S0 = PV(total cost of S0) - PV(total cost of scenario)
%
% 해석:
%   NPV_vs_S0 > 0  : 해당 시나리오가 S0보다 경제적
%   NPV_vs_S0 = 0  : S0와 동일
%   NPV_vs_S0 < 0  : 해당 시나리오가 S0보다 불리
%
% 주의:
%   cost.table의 각 비용은 이미 할인계수가 곱해진 현재가치(PV)이다.
%   따라서 연도별 NPV 기여분은 S0의 연도별 현재가치 비용과
%   해당 시나리오의 연도별 현재가치 비용의 차이로 계산한다.
% ------------------------------------------------------------

n = numel(scenarioResults);

scenario_id = strings(n,1);
scenario_name = strings(n,1);
status = strings(n,1);
baseline_scenario_id = strings(n,1);
total_cost_PV_KRW = nan(n,1);
baseline_total_cost_PV_KRW = nan(n,1);
operation_saving_vs_S0_PV_KRW = nan(n,1);
design_cost_increment_vs_S0_PV_KRW = nan(n,1);
NPV_vs_S0_KRW = nan(n,1);
NPV_rate_vs_S0_percent = nan(n,1);
economic_decision = strings(n,1);

% 연도별 표는 동적으로 누적한다.
annual_scenario_id = strings(0,1);
annual_scenario_name = strings(0,1);
year = zeros(0,1);
baseline_total_cost_PV_KRW_y = zeros(0,1);
scenario_total_cost_PV_KRW_y = zeros(0,1);
annual_net_benefit_PV_KRW = zeros(0,1);
cumulative_NPV_KRW = zeros(0,1);

if n == 0 || ~isfield(scenarioResults{1}, 'cost')
    npvTable = table(scenario_id, scenario_name, status, baseline_scenario_id, total_cost_PV_KRW, ...
        baseline_total_cost_PV_KRW, operation_saving_vs_S0_PV_KRW, design_cost_increment_vs_S0_PV_KRW, ...
        NPV_vs_S0_KRW, NPV_rate_vs_S0_percent, economic_decision);
    annualNpvTable = table(annual_scenario_id, annual_scenario_name, year, baseline_total_cost_PV_KRW_y, ...
        scenario_total_cost_PV_KRW_y, annual_net_benefit_PV_KRW, cumulative_NPV_KRW);
    return;
end

base = scenarioResults{1};
baseCost = base.cost;
baseTotalPV = baseCost.totalPresentValue;
baseOperationPV = baseCost.operationCostPV;
baseDesignPV = baseCost.designCostPV;
baselineId = string(base.cfg.scenarioId);

for i = 1:n
    r = scenarioResults{i};
    scenario_id(i) = string(r.cfg.scenarioId);
    scenario_name(i) = string(r.cfg.scenarioName);
    status(i) = string(r.status);
    baseline_scenario_id(i) = baselineId;

    if ~isfield(r, 'cost')
        economic_decision(i) = "NOT_AVAILABLE";
        continue;
    end

    total_cost_PV_KRW(i) = r.cost.totalPresentValue;
    baseline_total_cost_PV_KRW(i) = baseTotalPV;
    operation_saving_vs_S0_PV_KRW(i) = baseOperationPV - r.cost.operationCostPV;
    design_cost_increment_vs_S0_PV_KRW(i) = r.cost.designCostPV - baseDesignPV;
    NPV_vs_S0_KRW(i) = baseTotalPV - r.cost.totalPresentValue;

    if abs(baseTotalPV) > eps
        NPV_rate_vs_S0_percent(i) = 100 * NPV_vs_S0_KRW(i) / baseTotalPV;
    end

    if i == 1
        economic_decision(i) = "BASELINE";
    elseif ~strcmpi(r.status, 'OPTIMAL')
        economic_decision(i) = "NOT_PROVEN_" + string(r.status);
    elseif NPV_vs_S0_KRW(i) > 0
        economic_decision(i) = "ECONOMIC_vs_S0";
    elseif abs(NPV_vs_S0_KRW(i)) <= 1e-6
        economic_decision(i) = "BREAKEVEN_vs_S0";
    else
        economic_decision(i) = "NOT_ECONOMIC_vs_S0";
    end

    % 연도별 NPV 기여분 계산
    if height(r.cost.table) == height(baseCost.table)
        cumVal = 0;
        for y = 1:height(baseCost.table)
            annualBenefit = baseCost.table.total_cost_PV_KRW(y) - r.cost.table.total_cost_PV_KRW(y);
            cumVal = cumVal + annualBenefit;

            annual_scenario_id(end+1,1) = string(r.cfg.scenarioId); %#ok<AGROW>
            annual_scenario_name(end+1,1) = string(r.cfg.scenarioName); %#ok<AGROW>
            year(end+1,1) = y; %#ok<AGROW>
            baseline_total_cost_PV_KRW_y(end+1,1) = baseCost.table.total_cost_PV_KRW(y); %#ok<AGROW>
            scenario_total_cost_PV_KRW_y(end+1,1) = r.cost.table.total_cost_PV_KRW(y); %#ok<AGROW>
            annual_net_benefit_PV_KRW(end+1,1) = annualBenefit; %#ok<AGROW>
            cumulative_NPV_KRW(end+1,1) = cumVal; %#ok<AGROW>
        end
    end
end

npvTable = table(scenario_id, scenario_name, status, baseline_scenario_id, total_cost_PV_KRW, ...
    baseline_total_cost_PV_KRW, operation_saving_vs_S0_PV_KRW, design_cost_increment_vs_S0_PV_KRW, ...
    NPV_vs_S0_KRW, NPV_rate_vs_S0_percent, economic_decision);

annualNpvTable = table(annual_scenario_id, annual_scenario_name, year, baseline_total_cost_PV_KRW_y, ...
    scenario_total_cost_PV_KRW_y, annual_net_benefit_PV_KRW, cumulative_NPV_KRW);

end

function savedFiles = save_scenario_analysis_outputs_revised(out, baseCfg)
% save_scenario_analysis_outputs_revised
% ------------------------------------------------------------
% 전체 시나리오 비교표와 Excel 검증용 파일을 저장한다.
% ------------------------------------------------------------

savedFiles = struct();

if ~baseCfg.saveResults
    return;
end

if ~exist(baseCfg.outputDir, 'dir')
    mkdir(baseCfg.outputDir);
end

comparisonCsv = fullfile(baseCfg.outputDir, 'scenario_comparison_table.csv');
definitionCsv = fullfile(baseCfg.outputDir, 'scenario_definition_table.csv');
comparisonXlsx = fullfile(baseCfg.outputDir, 'scenario_comparison_table.xlsx');
npvCsv = fullfile(baseCfg.outputDir, 'scenario_npv_table.csv');
annualNpvCsv = fullfile(baseCfg.outputDir, 'scenario_annual_npv_table.csv');
verificationExcel = fullfile(baseCfg.outputDir, 'scenario_excel_verification_output.xlsx');
matFile = fullfile(baseCfg.outputDir, 'scenario_analysis_result.mat');

writetable(out.comparisonTable, comparisonCsv);
writetable(out.scenarioDefinition, definitionCsv);
if isfield(out, 'npvTable')
    writetable(out.npvTable, npvCsv);
end
if isfield(out, 'annualNpvTable')
    writetable(out.annualNpvTable, annualNpvCsv);
end

try
    writetable(out.scenarioDefinition, comparisonXlsx, 'Sheet', 'scenario_definition');
    writetable(out.comparisonTable, comparisonXlsx, 'Sheet', 'scenario_comparison');
    if isfield(out, 'npvTable')
        writetable(out.npvTable, comparisonXlsx, 'Sheet', 'scenario_npv');
    end
    if isfield(out, 'annualNpvTable')
        writetable(out.annualNpvTable, comparisonXlsx, 'Sheet', 'annual_npv');
    end
catch ME
    fprintf('[WARN] scenario_comparison_table.xlsx 저장 실패: %s\n', ME.message);
end

try
    writetable(out.scenarioDefinition, verificationExcel, 'Sheet', 'scenario_definition');
    writetable(out.comparisonTable, verificationExcel, 'Sheet', 'scenario_comparison');
    if isfield(out, 'npvTable')
        writetable(out.npvTable, verificationExcel, 'Sheet', 'scenario_npv');
    end
    if isfield(out, 'annualNpvTable')
        writetable(out.annualNpvTable, verificationExcel, 'Sheet', 'annual_npv');
    end

    for i = 1:numel(out.scenarios)
        r = out.scenarios{i};
        sid = char(r.cfg.scenarioId);
        if isfield(r, 'sol')
            writetable(r.sol.annualTable, verificationExcel, 'Sheet', [sid, '_annual']);
            writetable(r.cost.table, verificationExcel, 'Sheet', [sid, '_cost']);
            verifyTable = build_excel_verification_table_revised(r.sol, r.data, r.cfg, r.meta);
            writetable(verifyTable, verificationExcel, 'Sheet', [sid, '_verify']);

            % 전체 dispatch는 8760h x 20년에서도 Excel 한계 이하이나, 파일 용량이 커질 수 있다.
            % 검증용 핵심 잔차는 *_verify 시트에 있으므로 dispatch는 별도 CSV도 함께 저장한다.
            dispatchFile = fullfile(baseCfg.outputDir, ['scenario_', sid, '_dispatch_for_excel.csv']);
            writetable(r.sol.dispatchTable, dispatchFile);
            savedFiles.(['dispatchCsv_', sid]) = dispatchFile;
        end
    end
catch ME
    fprintf('[WARN] Excel 검증용 파일 저장 실패: %s\n', ME.message);
end

outSaved = out; %#ok<NASGU>
save(matFile, 'outSaved');

savedFiles.comparisonCsv = comparisonCsv;
savedFiles.definitionCsv = definitionCsv;
savedFiles.comparisonXlsx = comparisonXlsx;
savedFiles.npvCsv = npvCsv;
savedFiles.annualNpvCsv = annualNpvCsv;
savedFiles.verificationExcel = verificationExcel;
savedFiles.matFile = matFile;

fprintf('\n================ Scenario Output Files ================\n');
fprintf('Scenario definition CSV : %s\n', definitionCsv);
fprintf('Scenario comparison CSV : %s\n', comparisonCsv);
fprintf('Scenario comparison XLSX: %s\n', comparisonXlsx);
fprintf('Scenario NPV CSV       : %s\n', npvCsv);
fprintf('Annual NPV CSV         : %s\n', annualNpvCsv);
fprintf('Excel verification XLSX : %s\n', verificationExcel);
fprintf('MAT scenario result     : %s\n', matFile);

end

function verifyTable = build_excel_verification_table_revised(sol, data, cfg, meta)
% build_excel_verification_table_revised
% ------------------------------------------------------------
% Excel에서 MATLAB/Gurobi 해를 검산하기 위한 시간별 잔차표를 만든다.
% 각 행은 특정 연도 y, 시간 t에 대한 전력수지, SOC, PCS, 계약전력 제약의 잔차를 포함한다.
% ------------------------------------------------------------

T = data.T;
Y = cfg.projectYears;
N = T * Y;
dt = data.dt_h;

scenario_id = strings(N,1);
Year = zeros(N,1);
Timestamp = repmat(data.ts(:), Y, 1);
Load_kW = zeros(N,1);
PV_kW = zeros(N,1);
Price_KRW_per_kWh = zeros(N,1);
E_ESS_kWh = zeros(N,1);
E_usable_kWh = zeros(N,1);
P_PCS_kW = zeros(N,1);
P_contract_kW = zeros(N,1);
P_exceed_kW = zeros(N,1);
P_grid_kW = zeros(N,1);
P_ch_kW = zeros(N,1);
P_dis_kW = zeros(N,1);
SOC_kWh = zeros(N,1);
U_ch = zeros(N,1);
P_pv_use_kW = zeros(N,1);
P_pv_curt_kW = zeros(N,1);

power_balance_residual_kW = zeros(N,1);
soc_dynamic_residual_kWh = zeros(N,1);
soc_upper_violation_kWh = zeros(N,1);
soc_lower_violation_kWh = zeros(N,1);
pcs_charge_violation_kW = zeros(N,1);
pcs_discharge_violation_kW = zeros(N,1);
contract_violation_kW = zeros(N,1);
simultaneous_charge_discharge_kW = zeros(N,1);
simultaneous_charge_discharge_kW2 = zeros(N,1);
terminal_soc_residual_kWh = zeros(N,1);
duration_min_violation_kWh = zeros(N,1);
duration_max_violation_kWh = zeros(N,1);

pos = 0;
for y = 1:Y
    loadY = data.load_kW(:) * meta.loadMultiplier(y);
    pvY = data.pv_kW(:) * meta.pvMultiplier(y);
    priceY = data.price_KRW_per_kWh(:) * meta.energyPriceMultiplier(y);

    for t = 1:T
        pos = pos + 1;
        scenario_id(pos) = string(cfg.scenarioId);
        Year(pos) = y;
        Load_kW(pos) = loadY(t);
        PV_kW(pos) = pvY(t);
        Price_KRW_per_kWh(pos) = priceY(t);
        E_ESS_kWh(pos) = sol.E_ESS_kWh(y);
        E_usable_kWh(pos) = sol.E_usable_kWh(y);
        P_PCS_kW(pos) = sol.P_PCS_kW(y);
        P_contract_kW(pos) = sol.P_contract_kW(y);
        P_exceed_kW(pos) = sol.P_exceed_kW(y);
        P_grid_kW(pos) = sol.p_grid_kW(t,y);
        P_ch_kW(pos) = sol.p_ch_kW(t,y);
        P_dis_kW(pos) = sol.p_dis_kW(t,y);
        SOC_kWh(pos) = sol.soc_kWh(t,y);
        U_ch(pos) = sol.u_ch(t,y);
        P_pv_use_kW(pos) = sol.p_pv_use_kW(t,y);
        P_pv_curt_kW(pos) = sol.p_pv_curt_kW(t,y);

        if cfg.usePV
            power_balance_residual_kW(pos) = sol.p_grid_kW(t,y) - sol.p_ch_kW(t,y) + sol.p_dis_kW(t,y) + sol.p_pv_use_kW(t,y) - loadY(t);
        else
            power_balance_residual_kW(pos) = sol.p_grid_kW(t,y) - sol.p_ch_kW(t,y) + sol.p_dis_kW(t,y) - loadY(t);
        end

        if t == 1
            socPrev = cfg.socInitial * sol.E_usable_kWh(y);
        else
            socPrev = sol.soc_kWh(t-1,y);
        end
        soc_dynamic_residual_kWh(pos) = sol.soc_kWh(t,y) - socPrev - cfg.etaCharge * sol.p_ch_kW(t,y) * dt + sol.p_dis_kW(t,y) * dt / cfg.etaDischarge;

        soc_upper_violation_kWh(pos) = max(0, sol.soc_kWh(t,y) - cfg.socMax * sol.E_usable_kWh(y));
        soc_lower_violation_kWh(pos) = max(0, cfg.socMin * sol.E_usable_kWh(y) - sol.soc_kWh(t,y));
        pcs_charge_violation_kW(pos) = max(0, sol.p_ch_kW(t,y) - sol.P_PCS_kW(y));
        pcs_discharge_violation_kW(pos) = max(0, sol.p_dis_kW(t,y) - sol.P_PCS_kW(y));
        contract_violation_kW(pos) = max(0, sol.p_grid_kW(t,y) - sol.P_contract_kW(y) - sol.P_exceed_kW(y));
        simultaneous_charge_discharge_kW(pos) = min(sol.p_ch_kW(t,y), sol.p_dis_kW(t,y));
        simultaneous_charge_discharge_kW2(pos) = sol.p_ch_kW(t,y) * sol.p_dis_kW(t,y);

        if t == T
            terminal_soc_residual_kWh(pos) = sol.soc_kWh(t,y) - cfg.socInitial * sol.E_usable_kWh(y);
        end

        if cfg.enforceDuration
            duration_min_violation_kWh(pos) = max(0, cfg.durationMin_h * sol.P_PCS_kW(y) - sol.E_ESS_kWh(y));
            if isfinite(cfg.durationMax_h)
                duration_max_violation_kWh(pos) = max(0, sol.E_ESS_kWh(y) - cfg.durationMax_h * sol.P_PCS_kW(y));
            else
                duration_max_violation_kWh(pos) = 0;
            end
        end
    end
end

verifyTable = table( ...
    scenario_id, Year, Timestamp, Load_kW, PV_kW, Price_KRW_per_kWh, ...
    E_ESS_kWh, E_usable_kWh, P_PCS_kW, P_contract_kW, P_exceed_kW, ...
    P_grid_kW, P_ch_kW, P_dis_kW, SOC_kWh, U_ch, P_pv_use_kW, P_pv_curt_kW, ...
    power_balance_residual_kW, soc_dynamic_residual_kWh, soc_upper_violation_kWh, soc_lower_violation_kWh, ...
    pcs_charge_violation_kW, pcs_discharge_violation_kW, contract_violation_kW, ...
    simultaneous_charge_discharge_kW, simultaneous_charge_discharge_kW2, ...
    terminal_soc_residual_kWh, duration_min_violation_kWh, duration_max_violation_kWh);

end

%% ============================================================
%  Configuration
% =============================================================
function cfg = config_ess_revised()
% config_ess_revised
% ------------------------------------------------------------
% 논문 계산 조건을 한 곳에서 수정하기 위한 설정값 모음
% ------------------------------------------------------------

cfg = struct();

% ---------- 시나리오 기본값 ----------
cfg.scenarioId = 'BASE';
cfg.scenarioName = 'BASE_SINGLE_RUN';
cfg.scenarioDescription = '기본 단일 실행 설정';
cfg.useESS = true;

% ---------- 입력 데이터 모드 / 진단 실험 설정 ----------
% TEST  : 빠른 모델 검증용 168시간 부하 파일 사용
% PAPER : 실제 논문용 입력 파일 사용
% BASE        : 기준 비용 조건
% CAPEX_ZERO  : ESS/PCS 투자비, 유지보수비, 교체비를 0으로 두는 모델 작동 검증 실험
% BASIC_X5    : 기본요금 단가를 5배로 두어 계약전력/기본요금 구조가 ESS 설치를 유도하는지 검증
% FORCED_ESS  : ESS/PCS 최소 설치용량을 강제하여 충방전·SOC·계약전력 제약을 검증
cfg.inputDatasetMode = 'PAPER';        % 'TEST' 또는 'PAPER'
cfg.experimentCase   = 'CAPEX_SENSITIVITY';  % 'BASE', 'CAPEX_ZERO', 'BASIC_X5', 'FORCED_ESS', 'CAPEX_SENSITIVITY'
cfg.paperInputFile    = 'load_input_1.csv';
cfg.testInputFile     = 'load_input_test_168h.csv';

% ---------- 입력 파일 ----------
% 실제 입력 파일명은 apply_experiment_case_revised()에서 inputDatasetMode에 따라 결정된다.
cfg.inputFile  = cfg.paperInputFile;  % 기본값. TEST 모드에서는 cfg.testInputFile로 자동 변경
cfg.timeColumn = 'timestamp';
cfg.loadColumn = 'load_kWh';
cfg.pvColumn   = 'pv_kWh';
cfg.priceColumn = 'price_KRW_per_kWh';
cfg.allowSyntheticData = false;
cfg.timeFormat = '';

% ---------- 시간 설정 ----------
cfg.dt_h = 1.0;
cfg.resampleToHourly = true;

% ---------- 다년도 분석 ----------
cfg.projectYears = 20;
cfg.discountRate = 0.045;
cfg.loadGrowthRate = 0.015;       % 매년 부하 증가율
cfg.pvGrowthRate = 0.000;         % PV가 있을 때 연간 PV 발전량 증가율
cfg.energyPriceEscalationRate = 0.000;
cfg.basicPriceEscalationRate = 0.000;

% 현재가치
cfg.costEvaluationMode = 'present_value';

% ---------- 논문용 기준값 출처 요약 ----------
% 1) 전기요금: 교육용(을) 고압A 선택II, 적용일자 2023-11-09.
%    - 계약전력 1,000 kW 이상 교육용 고객에 적용.
%    - 계절: 여름 6~8월, 봄·가을 3~5/9~10월, 겨울 11~2월.
%    - 시간대: KEPCO TOU 경부하/중간부하/최대부하 구분을 input_load CSV에 직접 반영.
% 2) ESS/PCS 비용: NREL ATB/Ramasamy 계열 commercial BESS benchmark를 KRW로 환산.
%    - 2023 평균환율 1306.7637 KRW/USD 적용.
% 3) 할인율: 공공투자 경제성 분석의 사회적 할인율 4.5% 적용.
% 4) 수전설비 증설비: 국내 문헌의 수전설비 비용 120천원/kW 가정값 적용.
% ------------------------------------------------

% ---------- PV 옵션 ----------
cfg.usePV = false;

% ---------- 계약전력 옵션 ----------
% 'forbid'  : 계약전력 초과 불가
% 'penalty' : 계약전력 초과 허용, penalty 비용 부과
cfg.contractMode = 'forbid';
cfg.optimizeContract = true;

% 고정 계약전력 설정
% - single_value       : cfg.contractFixed_kW 하나의 값으로 전 연도 고정
% - annual_noess_peak  : No-ESS 기준 연도별 최대부하로 매년 갱신
% 논문용 A안에서는 annual_noess_peak가 가장 논리적이다.
cfg.contractFixedMode = 'annual_noess_peak';
cfg.contractFixed_kW = 3000;              % single_value 모드 또는 수동 백업값
cfg.contractFixedByYear_kW = [];          % finalize_fixed_contract_by_year_revised에서 자동 생성
cfg.contractFixedMargin = 0.00;           % 여유율. 예: 0.01이면 1% 여유
cfg.contractRoundingUnit_kW = 1;          % 계약전력 올림 단위. 예: 10이면 10 kW 단위 올림
cfg.contractFixedUseGridPeak = true;      % PV 사용 시 load-PV의 계통구매 피크를 기준으로 함

% 첫해 기준 고정 계약전력에 맞추어 초기 수전설비 용량을 자동 보정한다.
% false로 두면 cfg.initialFacilityCapacity_kW를 사용자가 지정한 값으로 유지한다.
cfg.autoSetInitialFacilityFromFirstFixedContract = true;

cfg.contractMin_kW   = 500;
cfg.contractMax_kW   = 10000;       % 초기 기본값. 데이터 로드 후 tighten_upper_bounds_from_data_revised에서 자동 축소 가능
cfg.penaltyExceed_KRW_per_kW_year = 1000000;

% ---------- 상한값 자동 축소 옵션 ----------
% TIME_LIMIT 완화를 위해 입력 부하와 부하증가율을 기준으로 계약전력/PCS/수전설비 상한을 자동 재설정한다.
% 기본 로직:
%   peakMax = max_y max_t P_grid_noESS(t,y)
%   contractMax_kW = ceil((1+safetyMargin)*peakMax)
%   P_max_kW       = ceil((1+safetyMargin)*peakMax)
%   facilityInstalledMax_kW = ceil(facilityMargin*contractMax_kW)
% E_max_kWh는 기존 설정값보다 더 작은 경우에만 durationMax_h*P_max_kW 기준으로 줄인다.
cfg.autoTightenUpperBounds = true;
cfg.contractMaxSafetyMargin = 0.05;   % 계약전력 최적화 상한 여유율. 예: 최종연도 피크의 105%
cfg.PmaxSafetyMargin = 0.00;          % PCS 출력 상한 여유율. 일반적으로 No-ESS 피크 초과 PCS는 불필요
cfg.tightenEmaxByDuration = true;
cfg.tightenFacilityMaxByContract = true;

% ---------- 수전설비 증설 옵션 ----------
% 필요 수전설비용량 = facilityMargin * P_contract
% 실제 설치 설비용량은 감소하지 않는다고 보는 것이 물리적으로 타당하다.
cfg.facilityMargin = 1.20;
cfg.initialFacilityCapacity_kW = cfg.facilityMargin * cfg.contractFixed_kW;
cfg.facilityExpansionCost_KRW_per_kW = 120000;  % 수전설비 비용 가정: 국내 수전설비 비용 120천원/kW 문헌값 적용
cfg.facilityInstalledMax_kW = 20000;

% ---------- ESS/PCS 설비 범위 ----------
cfg.E_min_kWh = 0;
cfg.E_max_kWh = 30000;       % 초기 기본값. durationMax_h*P_max_kW가 더 작으면 자동 축소
cfg.P_min_kW = 0;
cfg.P_max_kW = 10000;        % 초기 기본값. 데이터 로드 후 자동 축소 가능

% 기존 설치 ESS/PCS가 있으면 여기에 입력한다. 신규 설치라면 0.
cfg.initialESSInstalled_kWh = 0;
cfg.initialPCSInstalled_kW = 0;

% 실제 설비 투자 관점에서는 설치 용량이 감소하지 않는 것이 타당하다.
cfg.enforceNondecreasingESSCapacity = true;

% ESS 지속시간 제약
cfg.enforceDuration = true;
cfg.durationMin_h = 1.0;
cfg.durationMax_h = 10.0;

% 충전/방전 동시발생 방지 binary
% 8760시간 x 20년에서 true이면 u_ch binary가 175,200개 생성되어 TIME_LIMIT의 주된 원인이 된다.
% 기본값은 false로 두어 완화 LP/MILP를 먼저 풀고, 아래 동시 충방전 진단값으로 물리적 오류를 검증한다.
% 최종 논문용 엄격 MILP 검증 또는 대표일 모델에서는 true로 바꿔 재실행할 수 있다.
cfg.useBinaryChargeDischarge = false;

% binary 제거 시 퇴화해(degenerate solution)와 불필요한 순환 충방전을 줄이기 위한 매우 작은 보조항이다.
% 경제성 비용으로 해석하지 말고, 동시 충방전 방지용 수치 안정화 항으로만 사용한다.
cfg.smallCyclePenalty_KRW_per_kWh = 1.0;

% 계약전력 최적화 시 계약전력을 1 kW 정수 단위로 제한한다.
% S0/S1은 fixed contract를 올림 처리하므로, S2도 동일 단위로 비교해야 한다.
cfg.enforceIntegerContract = true;

% ---------- ESS 효율 및 SOC ----------
cfg.etaCharge = sqrt(0.85);       % NREL ATB 대표 왕복효율 85%를 충전/방전 대칭 효율로 분해
cfg.etaDischarge = sqrt(0.85);    % etaCharge*etaDischarge = 0.85
cfg.socMin = 0.20;
cfg.socMax = 0.80;
cfg.socInitial = 0.50;
cfg.enforceTerminalSOC = true;

% ---------- 요금 ----------
cfg.defaultFlatEnergyPrice_KRW_per_kWh = 106.9;  % 백업값. 실제 계산은 CSV의 TOU price 사용
cfg.basicCharge_KRW_per_kW_month = 6980;  % 교육용(을) 고압A 선택II 기본요금, 2023-11-09

% ---------- 투자비, 유지보수비, 교체비 ----------
cfg.capexESS_KRW_per_kWh = 846000;  % NREL 2022 commercial BESS total 672 USD/kWh 기준, PCS 97.5 USD/kW 분리 후 잔여를 에너지비로 환산
cfg.capexPCS_KRW_per_kW  = 127000;  % NREL battery central inverter 97.5 USD/kW * 2023 평균환율

% 유지보수비 = (ESS 투자비 + PCS 투자비)의 2.5%/year
% NREL ATB는 FOM을 capital cost의 2.5%로 제시한다.
cfg.omRateOfInstalledCost = 0.025;

% ---------- 열화 및 교체 ----------
% 자연열화 + 사이클 열화를 최적화 제약식에 직접 반영한다.
% 연도 y의 운전 가능 용량은 연초 열화 상태 기준으로 계산한다.
%   E_usable(y) = E_ESS(y) - degradation_begin(y)
% 연말에는 replacement 전 열화량을 먼저 계산한다.
%   degradation_pre_replace(y) = degradation_begin(y) + calendar_degradation(y) + cycle_degradation(y)
% SOH 80%, 즉 누적 용량손실 20%에 도달하면 binary z_replace_ESS(y)=1이 되고,
% 해당 연도 말에 ESS 전체 용량 E_ESS(y)를 교체한 것으로 보아 degradation_end(y)=0으로 초기화한다.
% 이 구현은 연 단위 교체 모델이다. 월/일/시간 단위 교체 시점까지 추적하지 않는다.
%
% cycleLife_EFC와 eolCapacityLossFraction의 의미:
%   - 6000 EFC에서 정격용량의 20%가 손실된다고 가정하면
%     사이클 열화 손실[kWh] = (0.20/6000) * 배터리 내부 방전량[kWh]
%   - 배터리 내부 방전량은 p_dis/etaDischarge 기준이다.
cfg.calendarDegradationRate_per_year = 0.20/15;  % 15년 기술수명과 SOH 80% EOL 기준을 연 단위 선형 자연열화로 보수적 환산
cfg.cycleLife_EFC = 5000;                        % LFP 기반 ESS 문헌의 5000 EFC, SOH 80% 기준 적용
cfg.eolCapacityLossFraction = 0.20;              % EOL 용량손실률, 예: 20%
cfg.replacementAtSOH = 0.80;                     % SOH 80% 도달 시 교체
cfg.replacementTriggerLossFraction = 1 - cfg.replacementAtSOH;
cfg.enforceEOLCapacityLimit = true;              % true이면 replacement 전 열화가 20%를 넘을 때 교체 binary를 강제
cfg.initialESSDegradation_kWh = 0;               % 기존 ESS가 있을 경우 초기 누적 열화손실[kWh]

% ESS 교체 모델
% includeESSDegradationBasedReplacement=true:
%   - z_replace_ESS(y) binary 사용
%   - degradation_pre_replace(y) > 20%*E_ESS(y)이면 z_replace_ESS(y)=1 필요
%   - z_replace_ESS(y)=1이면 E_replacement_kWh(y)=E_ESS(y), degradation_end(y)=0
% includeESSDegradationBasedReplacement=false:
%   - 교체 없음. 열화는 누적되고 20% 한계를 넘지 않도록 증설 또는 운전 변경 필요
cfg.includeESSDegradationBasedReplacement = true;
cfg.minESSCapacityForReplacement_kWh = 1e-3;     % E=0인 경우 replacement binary가 켜지지 않도록 하는 작은 하한
cfg.replacementBigM_kWh = cfg.E_max_kWh;         % 선형화용 Big-M. 보통 E_max_kWh 이상이면 충분
cfg.replacementESS_KRW_per_kWh = 260000;  % 배터리 팩 교체비: NREL 4h LIB pack 199 USD/kWh * 2023 평균환율

% PCS는 본 코드에서 열화 모델을 두지 않았다. 필요 시 별도 고장률/수명 모델로 확장해야 한다.
cfg.includeFixedPCSReplacementCost = true;
cfg.replacementPCS_KRW_per_kW  = 127000;  % PCS 교체비는 초기 PCS 단가와 동일하게 설정
cfg.pcsReplacementLife_year = 15;      % NREL ATB commercial battery storage technical life 15년과 정합

% ---------- Gurobi ----------
cfg.gurobiOutputFlag = 1;
cfg.mipGap = 1e-4;
cfg.timeLimitSec = 1800;
cfg.writeModelFile = true;
cfg.debugModelFile = 'debug_ess_model_paper_assumptions.lp';

% 성능 보조 설정
cfg.gurobiPresolve = 2;
cfg.gurobiCuts = 2;
cfg.gurobiMIPFocus = 3;
cfg.gurobiThreads = 0;
cfg.gurobiNumericFocus = 1;
cfg.gurobiNodefileStart = 0.5;
cfg.gurobiNodefileDir = '';  % cfg.outputDir 설정 후 아래에서 지정

% ---------- 출력 저장 ----------
cfg.saveResults = true;
cfg.outputDir = 'results_ess_paper_assumptions';
cfg.gurobiNodefileDir = fullfile(cfg.outputDir, 'gurobi_nodefiles');

% TEST/PAPER 및 진단 실험 조건을 마지막에 적용한다.
% 민감도 배치 실행 중이면 global override가 여기서 적용된다.
cfg = apply_capex_sensitivity_override_revised(cfg);
cfg = apply_experiment_case_revised(cfg);

end


function cfg = apply_capex_sensitivity_override_revised(cfg)
% apply_capex_sensitivity_override_revised
% ------------------------------------------------------------
% run_ess_gurobi_paper_capex_sensitivity() 배치 루프에서 전달한
% PAPER/CAPEX_SENSITIVITY/capexScale/outputDirSuffix 설정을 cfg에 반영한다.
% 일반 단독 실행 시에는 override가 비어 있으므로 아무 것도 변경하지 않는다.
% ------------------------------------------------------------

global ESS_CAPEX_SENSITIVITY_OVERRIDE;

if isempty(ESS_CAPEX_SENSITIVITY_OVERRIDE) || ~isstruct(ESS_CAPEX_SENSITIVITY_OVERRIDE)
    return;
end

f = fieldnames(ESS_CAPEX_SENSITIVITY_OVERRIDE);
for i = 1:numel(f)
    cfg.(f{i}) = ESS_CAPEX_SENSITIVITY_OVERRIDE.(f{i});
end

end

function cfg = apply_experiment_case_revised(cfg)
% apply_experiment_case_revised
% ------------------------------------------------------------
% 입력 데이터 모드와 진단 실험 조건을 일괄 적용한다.
% - TEST: 빠른 모델 검증용 168시간 부하 파일 사용, 분석기간 3년
% - PAPER: 실제 논문용 입력 파일 사용, 설정된 분석기간 유지
% - CAPEX_ZERO: ESS 투자비 0원 진단 실험
% - BASIC_X5: 기본요금 5배 진단 실험
% - FORCED_ESS: ESS/PCS 최소 설치 강제 진단 실험
% - CAPEX_SENSITIVITY: ESS 배터리 투자비 배율 민감도 분석
%
% 안전장치:
% cfg.inputDatasetMode 또는 cfg.experimentCase가 config_ess_revised()
% 내부에서 누락되어도 기본값을 자동 생성한다.
% 이 처리가 없으면 MATLAB에서 '인식할 수 없는 필드 이름' 오류가 발생한다.
% ------------------------------------------------------------

% ---------- 누락 필드 기본값 보정 ----------
if ~isfield(cfg, 'inputDatasetMode') || isempty(cfg.inputDatasetMode)
    cfg.inputDatasetMode = 'TEST';
end
if ~isfield(cfg, 'experimentCase') || isempty(cfg.experimentCase)
    cfg.experimentCase = 'CAPEX_SENSITIVITY';
end
if ~isfield(cfg, 'paperInputFile') || isempty(cfg.paperInputFile)
    cfg.paperInputFile = 'load_input_1.csv';
end
if ~isfield(cfg, 'testInputFile') || isempty(cfg.testInputFile)
    cfg.testInputFile = 'load_input_test_168h.csv';
end
if ~isfield(cfg, 'inputFile') || isempty(cfg.inputFile)
    cfg.inputFile = cfg.paperInputFile;
end

mode = upper(char(cfg.inputDatasetMode));
caseName = upper(char(cfg.experimentCase));

switch mode
    case 'TEST'
        cfg.inputFile = cfg.testInputFile;
        cfg.projectYears = 3;
        cfg.timeLimitSec = min(cfg.timeLimitSec, 300);
        cfg.outputDir = [cfg.outputDir, '_TEST'];
        cfg.writeModelFile = false;
    case 'PAPER'
        cfg.inputFile = cfg.paperInputFile;
    otherwise
        error('cfg.inputDatasetMode는 TEST 또는 PAPER이어야 합니다: %s', cfg.inputDatasetMode);
end

switch caseName
    case 'BASE'
        % 기준 조건. 수정 없음.

    case 'CAPEX_SENSITIVITY'
        % ESS 배터리 kWh 단가 민감도 분석.
        % PCS 투자비는 기준값으로 유지한다. PCS까지 함께 조정하려면 별도 실험으로 분리해야 한다.
        if ~isfield(cfg, 'capexESSScale') || isempty(cfg.capexESSScale)
            cfg.capexESSScale = 1.0;
        end
        if ~isfield(cfg, 'capexCaseLabel') || isempty(cfg.capexCaseLabel)
            cfg.capexCaseLabel = sprintf('CAPEX_%03d', round(100*cfg.capexESSScale));
        end
        if ~isfield(cfg, 'capexCaseTag') || isempty(cfg.capexCaseTag)
            cfg.capexCaseTag = sprintf('%03d', round(100*cfg.capexESSScale));
        end

        cfg.capexESSBase_KRW_per_kWh = cfg.capexESS_KRW_per_kWh;
        cfg.capexPCSBase_KRW_per_kW  = cfg.capexPCS_KRW_per_kW;
        cfg.capexESS_KRW_per_kWh = cfg.capexESSBase_KRW_per_kWh * cfg.capexESSScale;

        % case별 폴더 분리. outputDirSuffix가 있으면 배치 루프에서 지정한 suffix를 사용한다.
        if isfield(cfg, 'outputDirSuffix') && ~isempty(cfg.outputDirSuffix)
            cfg.outputDir = [cfg.outputDir, char(cfg.outputDirSuffix)];
        else
            cfg.outputDir = [cfg.outputDir, '_PAPER_CAPEX_', cfg.capexCaseTag];
        end

    case 'CAPEX_ZERO' 
        % ESS가 경제성 때문에 0이 되는지, 아니면 제약/구현 오류로 0이 되는지 확인하기 위한 진단 실험.
        % 논문 본 결과로 사용하지 말고 모델 정상 작동 검증용으로만 사용한다.
        cfg.capexESS_KRW_per_kWh = 0;
        cfg.capexPCS_KRW_per_kW  = 0;
        cfg.omRateOfInstalledCost = 0;
        cfg.replacementESS_KRW_per_kWh = 0;
        cfg.replacementPCS_KRW_per_kW  = 0;
        cfg.outputDir = [cfg.outputDir, '_CAPEX_ZERO'];

    case 'BASIC_X5'
        % 기본요금 5배 진단 실험.
        % 목적: 계약전력 최적화와 기본요금 항이 ESS 설치 및 피크저감을 유도하는지 확인한다.
        % 주의: 논문 본 결과가 아니라 모델 작동 검증용 조건이다.
        cfg.basicChargeBase_KRW_per_kW_month = cfg.basicCharge_KRW_per_kW_month;
        cfg.basicChargeMultiplier = 5.0;
        cfg.basicCharge_KRW_per_kW_month = cfg.basicChargeMultiplier * cfg.basicCharge_KRW_per_kW_month;
        cfg.outputDir = [cfg.outputDir, '_BASIC_X5'];

    case 'FORCED_ESS'
        % ESS 강제 설치 진단 실험.
        % 목적: 투자비가 존재하는 조건에서 ESS가 양의 설비용량을 가질 때
        %       전력수지, SOC, PCS 출력, 계약전력, 동시충방전 검증값이 정상인지 확인한다.
        % 주의: 경제적 최적 설치 여부를 판단하는 실험이 아니라 제약조건 검증용 실험이다.
        cfg.E_min_kWh = 1000;
        cfg.P_min_kW  = 500;
        cfg.forcedESS_E_min_kWh = cfg.E_min_kWh;
        cfg.forcedESS_P_min_kW = cfg.P_min_kW;
        cfg.outputDir = [cfg.outputDir, '_FORCED_ESS'];

    otherwise
        error('cfg.experimentCase는 BASE, CAPEX_ZERO, BASIC_X5, FORCED_ESS, CAPEX_SENSITIVITY 중 하나여야 합니다: %s', cfg.experimentCase);
end

cfg.gurobiNodefileDir = fullfile(cfg.outputDir, 'gurobi_nodefiles');

fprintf('\n================ Run Mode ================\n');
fprintf('inputDatasetMode : %s\n', cfg.inputDatasetMode);
fprintf('experimentCase   : %s\n', cfg.experimentCase);
fprintf('inputFile        : %s\n', cfg.inputFile);
fprintf('projectYears     : %d\n', cfg.projectYears);
fprintf('outputDir        : %s\n', cfg.outputDir);
if isfield(cfg, 'capexESSScale')
    fprintf('capexESSScale   : %.3f\n', cfg.capexESSScale);
    fprintf('capexESS_KRW/kWh: %.6g\n', cfg.capexESS_KRW_per_kWh);
end

end



%% ============================================================
%  Automatic bound tightening helper
% =============================================================
function cfg = tighten_upper_bounds_from_data_revised(cfg, data)
% tighten_upper_bounds_from_data_revised
% ------------------------------------------------------------
% 입력 부하, PV, 연간 부하증가율을 반영하여 불필요하게 큰 상한값을 자동 축소한다.
%
% 이 함수의 목적은 해의 경제성 자체를 바꾸는 것이 아니라 다음을 줄이는 것이다.
%   1) 계약전력 변수 P_contract의 불필요한 탐색 범위
%   2) PCS 출력 변수 P_PCS 및 시간별 p_ch/p_dis의 상한
%   3) 충방전 binary 사용 시 Big-M 계수
%   4) 수전설비 설치용량 facility_installed의 상한
%
% 주의:
%   - 본 함수는 기준 부하 피크보다 큰 PCS/계약전력 해가 필요하지 않다는 보수적 가정에 기반한다.
%   - 전력 판매, 음수 전력가격, 대규모 PV 잉여 흡수 목적이 있으면 여유율을 키우거나 자동 축소를 끄는 것이 맞다.
%   - 현재 논문 조건(PV 미사용, 판매 없음, 계약전력 초과 forbid)에서는 계산 안정성 개선에 유효하다.
% ------------------------------------------------------------

if ~isfield(cfg, 'autoTightenUpperBounds') || ~cfg.autoTightenUpperBounds
    return;
end

if ~isfield(cfg, 'contractMaxSafetyMargin') || isempty(cfg.contractMaxSafetyMargin)
    cfg.contractMaxSafetyMargin = 0.05;
end
if ~isfield(cfg, 'PmaxSafetyMargin') || isempty(cfg.PmaxSafetyMargin)
    cfg.PmaxSafetyMargin = 0.00;
end
if ~isfield(cfg, 'tightenEmaxByDuration') || isempty(cfg.tightenEmaxByDuration)
    cfg.tightenEmaxByDuration = true;
end
if ~isfield(cfg, 'tightenFacilityMaxByContract') || isempty(cfg.tightenFacilityMaxByContract)
    cfg.tightenFacilityMaxByContract = true;
end
if ~isfield(cfg, 'contractRoundingUnit_kW') || isempty(cfg.contractRoundingUnit_kW) || cfg.contractRoundingUnit_kW <= 0
    cfg.contractRoundingUnit_kW = 1;
end

Y = cfg.projectYears;
noessPeakByYear = zeros(Y,1);
for y = 1:Y
    noessPeakByYear(y) = noess_peak_for_year_revised(cfg, data, y);
end

peakMax_kW = max(noessPeakByYear);

oldContractMax = cfg.contractMax_kW;
oldPmax = cfg.P_max_kW;
oldEmax = cfg.E_max_kWh;
oldFacilityMax = cfg.facilityInstalledMax_kW;
oldReplacementM = cfg.replacementBigM_kWh;

% 계약전력 최적화 상한: 최종연도 또는 분석기간 최대 No-ESS 계통구매 피크에 안전여유를 둔다.
rawContractMax = (1 + cfg.contractMaxSafetyMargin) * peakMax_kW;
autoContractMax = round_up_contract_revised(max(cfg.contractMin_kW, rawContractMax), cfg.contractRoundingUnit_kW);
cfg.contractMax_kW = autoContractMax;

% PCS 출력 상한: 계통 판매가 없으면 방전출력은 No-ESS 부하 피크를 초과할 실익이 거의 없다.
rawPmax = (1 + cfg.PmaxSafetyMargin) * peakMax_kW;
cfg.P_max_kW = ceil(max(cfg.P_min_kW, rawPmax));

% ESS 용량 상한: 기존 E_max보다 durationMax_h*P_max가 더 작은 경우에만 축소한다.
% 기존값보다 크게 늘리지는 않는다. 상한 축소 목적이므로 보수적으로 처리한다.
if cfg.tightenEmaxByDuration && isfield(cfg, 'enforceDuration') && cfg.enforceDuration && isfinite(cfg.durationMax_h)
    autoEmax = ceil(cfg.durationMax_h * cfg.P_max_kW);
    cfg.E_max_kWh = min(cfg.E_max_kWh, autoEmax);
end

% 수전설비 설치상한: 계약전력 상한의 facilityMargin 배수 이상이면 충분하다.
if cfg.tightenFacilityMaxByContract
    cfg.facilityInstalledMax_kW = ceil(cfg.facilityMargin * cfg.contractMax_kW);
end

% 교체 및 열화 선형화 Big-M은 E_max와 일치시킨다.
cfg.replacementBigM_kWh = cfg.E_max_kWh;

fprintf('\n================ Automatic Upper-Bound Tightening ================\n');
fprintf('autoTightenUpperBounds     : true\n');
fprintf('No-ESS peak y01/yEnd/max   : %.3f / %.3f / %.3f kW\n', noessPeakByYear(1), noessPeakByYear(end), peakMax_kW);
fprintf('contractMax_kW             : %.3f -> %.3f kW\n', oldContractMax, cfg.contractMax_kW);
fprintf('P_max_kW                   : %.3f -> %.3f kW\n', oldPmax, cfg.P_max_kW);
fprintf('E_max_kWh                  : %.3f -> %.3f kWh\n', oldEmax, cfg.E_max_kWh);
fprintf('facilityInstalledMax_kW    : %.3f -> %.3f kW\n', oldFacilityMax, cfg.facilityInstalledMax_kW);
fprintf('replacementBigM_kWh        : %.3f -> %.3f kWh\n', oldReplacementM, cfg.replacementBigM_kWh);
fprintf('contractMaxSafetyMargin    : %.3f\n', cfg.contractMaxSafetyMargin);
fprintf('PmaxSafetyMargin           : %.3f\n', cfg.PmaxSafetyMargin);

end

%% ============================================================
%  Annual fixed contract helper
% =============================================================
function cfg = finalize_fixed_contract_by_year_revised(cfg, data)
% finalize_fixed_contract_by_year_revised
% ------------------------------------------------------------
% S0/S1에서 사용할 연도별 고정 계약전력을 확정한다.
%
% 논문용 A안 기본 정의:
%   P_contract_fix(y) = max_t P_grid_noESS(y,t)
%
% PV 미사용이면 P_grid_noESS = load.
% PV 사용이고 cfg.contractFixedUseGridPeak=true이면 P_grid_noESS = max(load - PV, 0).
% 이 값은 최적화 변수가 아니라 외생 파라미터이며, S0/S1에서만 사용된다.
% ------------------------------------------------------------

Y = cfg.projectYears;
fixed = zeros(Y,1);

if ~isfield(cfg, 'contractFixedMode') || isempty(cfg.contractFixedMode)
    cfg.contractFixedMode = 'single_value';
end
if ~isfield(cfg, 'contractFixedMargin') || isempty(cfg.contractFixedMargin)
    cfg.contractFixedMargin = 0;
end
if ~isfield(cfg, 'contractRoundingUnit_kW') || isempty(cfg.contractRoundingUnit_kW) || cfg.contractRoundingUnit_kW <= 0
    cfg.contractRoundingUnit_kW = 1;
end
if ~isfield(cfg, 'contractFixedUseGridPeak') || isempty(cfg.contractFixedUseGridPeak)
    cfg.contractFixedUseGridPeak = true;
end

switch lower(char(cfg.contractFixedMode))
    case 'single_value'
        fixed(:) = cfg.contractFixed_kW;

    case 'final_year_noess_peak'
        peakLast = noess_peak_for_year_revised(cfg, data, Y);
        fixed(:) = round_up_contract_revised((1 + cfg.contractFixedMargin) * peakLast, cfg.contractRoundingUnit_kW);

    case 'annual_noess_peak'
        for y = 1:Y
            peakY = noess_peak_for_year_revised(cfg, data, y);
            fixed(y) = round_up_contract_revised((1 + cfg.contractFixedMargin) * peakY, cfg.contractRoundingUnit_kW);
        end

    otherwise
        error('알 수 없는 cfg.contractFixedMode입니다: %s', cfg.contractFixedMode);
end

if any(~isfinite(fixed)) || any(fixed < 0)
    error('연도별 고정 계약전력 계산 결과가 비정상입니다.');
end

cfg.contractFixedByYear_kW = fixed(:);
cfg.contractFixed_kW = fixed(1);   % 기존 코드/출력 호환용 백업값

if isfield(cfg, 'autoSetInitialFacilityFromFirstFixedContract') && cfg.autoSetInitialFacilityFromFirstFixedContract
    cfg.initialFacilityCapacity_kW = cfg.facilityMargin * fixed(1);
end

fprintf('\n================ Fixed Contract Setting ================\n');
fprintf('contractFixedMode      : %s\n', cfg.contractFixedMode);
fprintf('contractFixed y01      : %.3f kW\n', fixed(1));
fprintf('contractFixed yEnd     : %.3f kW\n', fixed(end));
fprintf('contractFixed min/max  : %.3f / %.3f kW\n', min(fixed), max(fixed));
fprintf('initialFacilityCapacity: %.3f kW\n', cfg.initialFacilityCapacity_kW);

end

function fixed = get_fixed_contract_by_year_revised(cfg, Y)
% get_fixed_contract_by_year_revised
% ------------------------------------------------------------
% cfg.contractFixedByYear_kW가 있으면 이를 사용하고, 없으면
% cfg.contractFixed_kW 단일값을 전 연도에 반복 적용한다.
% ------------------------------------------------------------

if isfield(cfg, 'contractFixedByYear_kW') && ~isempty(cfg.contractFixedByYear_kW)
    fixed = cfg.contractFixedByYear_kW(:);
    if numel(fixed) ~= Y
        error('cfg.contractFixedByYear_kW 길이(%d)가 projectYears(%d)와 다릅니다.', numel(fixed), Y);
    end
else
    fixed = repmat(cfg.contractFixed_kW, Y, 1);
end

end

function peakY = noess_peak_for_year_revised(cfg, data, y)
% noess_peak_for_year_revised
% ------------------------------------------------------------
% y년차 No-ESS 계통구매전력 피크를 계산한다.
% ------------------------------------------------------------

loadY = data.load_kW(:) * (1 + cfg.loadGrowthRate)^(y-1);
pvY = data.pv_kW(:) * (1 + cfg.pvGrowthRate)^(y-1);

if cfg.usePV && cfg.contractFixedUseGridPeak
    gridNoESS = max(loadY - pvY, 0);
else
    gridNoESS = loadY;
end

peakY = max(gridNoESS);

end

function val = round_up_contract_revised(rawVal, roundingUnit)
% round_up_contract_revised
% ------------------------------------------------------------
% 계약전력을 지정 단위로 올림한다.
% roundingUnit=1이면 1 kW 단위, 10이면 10 kW 단위이다.
% ------------------------------------------------------------

if roundingUnit <= 0
    val = rawVal;
else
    val = ceil(rawVal / roundingUnit) * roundingUnit;
end

end

%% ============================================================
%  Data loading
% =============================================================
function data = load_ess_data_revised(cfg)
% load_ess_data_revised
% ------------------------------------------------------------
% CSV 데이터를 읽고 1시간 단위로 정리한다.
% load_kWh는 1시간 에너지이며, dt=1 h 기준 평균전력 kW로 변환한다.
% ------------------------------------------------------------

if ~isfile(cfg.inputFile)
    if cfg.allowSyntheticData
        fprintf('[WARN] 입력 파일이 없어 합성 데이터를 생성합니다. 논문 결과에는 사용하지 마십시오.\n');
        data = create_synthetic_data_revised(cfg);
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

[tsRaw, ord] = sort(tsRaw);
loadRaw_kWh = loadRaw_kWh(ord);
pvRaw_kWh = pvRaw_kWh(ord);
if hasPrice
    priceRaw = priceRaw(ord);
end

if cfg.resampleToHourly
    tsHour = dateshift(tsRaw, 'start', 'hour');
    [grp, tsGroup] = findgroups(tsHour);

    loadHour_kWh = splitapply(@sum, loadRaw_kWh, grp);
    pvHour_kWh = splitapply(@sum, pvRaw_kWh, grp);

    if hasPrice
        priceHour = splitapply(@mean, priceRaw, grp);
    else
        priceHour = cfg.defaultFlatEnergyPrice_KRW_per_kWh * ones(size(loadHour_kWh));
    end

    [ts, ord2] = sort(tsGroup);
    loadHour_kWh = loadHour_kWh(ord2);
    pvHour_kWh = pvHour_kWh(ord2);
    priceHour = priceHour(ord2);
else
    ts = tsRaw;
    loadHour_kWh = loadRaw_kWh;
    pvHour_kWh = pvRaw_kWh;
    if hasPrice
        priceHour = priceRaw;
    else
        priceHour = cfg.defaultFlatEnergyPrice_KRW_per_kWh * ones(size(loadHour_kWh));
    end
end

load_kW = loadHour_kWh / cfg.dt_h;
pv_kW = pvHour_kWh / cfg.dt_h;

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
data.yearScale = 8760 / n;

fprintf('\n================ Data Summary ================\n');
fprintf('Input file      : %s\n', cfg.inputFile);
fprintf('Number of hours : %d\n', n);
fprintf('Year scale      : %.6f\n', data.yearScale);
fprintf('Load min/mean/max [kW]: %.3f / %.3f / %.3f\n', min(data.load_kW), mean(data.load_kW), max(data.load_kW));
fprintf('Price min/mean/max [KRW/kWh]: %.3f / %.3f / %.3f\n', min(data.price_KRW_per_kWh), mean(data.price_KRW_per_kWh), max(data.price_KRW_per_kWh));

end

function data = create_synthetic_data_revised(cfg)
% create_synthetic_data_revised
% ------------------------------------------------------------
% 코드 테스트용 합성 부하 데이터 생성
% ------------------------------------------------------------

ts = (datetime(2025,1,1,0,0,0):hours(1):datetime(2025,12,31,23,0,0))';
n = numel(ts);
hourOfDay = hour(ts);
dayType = weekday(ts);
isWeekend = dayType == 1 | dayType == 7;
monthNo = month(ts);

summer = ismember(monthNo, [6 7 8]);
winter = ismember(monthNo, [12 1 2]);
classHours = hourOfDay >= 9 & hourOfDay <= 18;
nightBase = hourOfDay <= 6 | hourOfDay >= 22;

base = 1800;
daily = 1200 * classHours - 300 * nightBase;
weekendReduction = -500 * isWeekend;
seasonEffect = 900 * summer + 600 * winter;

rng(1);
noise = 120 * randn(n,1);
load_kW = max(500, base + daily + weekendReduction + seasonEffect + noise);
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
function [model, idx, meta] = build_ess_model_revised(cfg, data)
% build_ess_model_revised
% ------------------------------------------------------------
% 다년도 Gurobi MILP 모델을 생성한다.
% ------------------------------------------------------------

T = data.T;
Y = cfg.projectYears;
dt = data.dt_h;
N = T * Y;

meta = struct();
meta.discountFactor = zeros(Y,1);
meta.loadMultiplier = zeros(Y,1);
meta.pvMultiplier = zeros(Y,1);
meta.energyPriceMultiplier = zeros(Y,1);
meta.basicPriceMultiplier = zeros(Y,1);
meta.replacementPCSFlag = false(Y,1);

for y = 1:Y
    meta.discountFactor(y) = 1 / (1 + cfg.discountRate)^(y-1);
    meta.loadMultiplier(y) = (1 + cfg.loadGrowthRate)^(y-1);
    meta.pvMultiplier(y) = (1 + cfg.pvGrowthRate)^(y-1);
    meta.energyPriceMultiplier(y) = (1 + cfg.energyPriceEscalationRate)^(y-1);
    meta.basicPriceMultiplier(y) = (1 + cfg.basicPriceEscalationRate)^(y-1);

    if cfg.includeFixedPCSReplacementCost
        meta.replacementPCSFlag(y) = is_replacement_year(y, cfg.pcsReplacementLife_year);
    end
end

% S0/S1처럼 계약전력을 최적화하지 않는 시나리오에서 사용할 연도별 고정 계약전력
meta.contractFixedByYear_kW = get_fixed_contract_by_year_revised(cfg, Y);
meta.optimizationType = 'multiyear_integrated_simultaneous_MILP';
meta.optimizationDescription = ['20년 전체를 하나의 MILP로 동시에 푸는 다년도 통합 최적화이며, ', ...
    'ESS 용량, PCS 출력, 계약전력, 연도별 증설, 열화기반 교체, 시간별 운전을 동시에 결정한다.'];

% ---------- 변수 인덱스 생성 ----------
nvar = 0;
idx = struct();

idx.E = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Ppcs = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Pcon = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Pexc = (nvar+1):(nvar+Y); nvar = nvar + Y;

idx.facInst = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.facInc = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Einc = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Pinc = (nvar+1):(nvar+Y); nvar = nvar + Y;

% 열화 관련 연도별 변수
% Euse      : 열화 반영 후 사용 가능 ESS 용량[kWh]
% degBegin  : 해당 연도 시작 시 누적 열화손실[kWh]
% degCal    : 해당 연도 자연열화 손실[kWh/year]
% degCyc    : 해당 연도 사이클 열화 손실[kWh/year]
% degPre    : 교체 전 연말 누적 열화손실[kWh]
% degEnd    : 교체 후 연말 누적 열화손실[kWh]
% Erep      : 해당 연도 전체 ESS 교체 용량[kWh/year], Erep = E * zRep
% zRep      : ESS 전체 교체 여부 binary
idx.Euse = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.degBegin = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.degCal = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.degCyc = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.degPre = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.degEnd = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.Erep = (nvar+1):(nvar+Y); nvar = nvar + Y;
idx.zRep = (nvar+1):(nvar+Y); nvar = nvar + Y;

idx.pGrid = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
idx.pCh   = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
idx.pDis  = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
idx.soc   = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;

if cfg.useBinaryChargeDischarge
    idx.uCh = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
else
    idx.uCh = [];
end

if cfg.usePV
    idx.pvUse  = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
    idx.pvCurt = reshape((nvar+1):(nvar+N), T, Y); nvar = nvar + N;
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

for y = 1:Y
    varnames{idx.E(y)} = sprintf('E_ESS_kWh_y%02d', y);
    varnames{idx.Ppcs(y)} = sprintf('P_PCS_kW_y%02d', y);
    varnames{idx.Pcon(y)} = sprintf('P_contract_kW_y%02d', y);
    varnames{idx.Pexc(y)} = sprintf('P_exceed_kW_y%02d', y);
    varnames{idx.facInst(y)} = sprintf('facility_installed_kW_y%02d', y);
    varnames{idx.facInc(y)} = sprintf('facility_expansion_kW_y%02d', y);
    varnames{idx.Einc(y)} = sprintf('E_ESS_increment_kWh_y%02d', y);
    varnames{idx.Pinc(y)} = sprintf('P_PCS_increment_kW_y%02d', y);
    varnames{idx.Euse(y)} = sprintf('E_usable_kWh_y%02d', y);
    varnames{idx.degBegin(y)} = sprintf('degradation_begin_kWh_y%02d', y);
    varnames{idx.degCal(y)} = sprintf('calendar_degradation_kWh_y%02d', y);
    varnames{idx.degCyc(y)} = sprintf('cycle_degradation_kWh_y%02d', y);
    varnames{idx.degPre(y)} = sprintf('degradation_pre_replace_kWh_y%02d', y);
    varnames{idx.degEnd(y)} = sprintf('degradation_end_kWh_y%02d', y);
    varnames{idx.Erep(y)} = sprintf('E_replacement_kWh_y%02d', y);
    varnames{idx.zRep(y)} = sprintf('z_replace_ESS_y%02d', y);
end

for y = 1:Y
    for t = 1:T
        varnames{idx.pGrid(t,y)} = sprintf('p_grid_kW_y%02d_t%04d', y, t);
        varnames{idx.pCh(t,y)}   = sprintf('p_ch_kW_y%02d_t%04d', y, t);
        varnames{idx.pDis(t,y)}  = sprintf('p_dis_kW_y%02d_t%04d', y, t);
        varnames{idx.soc(t,y)}   = sprintf('soc_kWh_y%02d_t%04d', y, t);
        if cfg.useBinaryChargeDischarge
            varnames{idx.uCh(t,y)} = sprintf('u_ch_y%02d_t%04d', y, t);
        end
        if cfg.usePV
            varnames{idx.pvUse(t,y)}  = sprintf('p_pv_use_kW_y%02d_t%04d', y, t);
            varnames{idx.pvCurt(t,y)} = sprintf('p_pv_curt_kW_y%02d_t%04d', y, t);
        end
    end
end

% 설비 변수 bound
lb(idx.E) = cfg.E_min_kWh;
ub(idx.E) = cfg.E_max_kWh;
lb(idx.Ppcs) = cfg.P_min_kW;
ub(idx.Ppcs) = cfg.P_max_kW;
lb(idx.Einc) = 0;
lb(idx.Pinc) = 0;

% 열화 관련 변수 bound
lb(idx.Euse) = 0;
ub(idx.Euse) = cfg.E_max_kWh;
lb(idx.degBegin) = 0;
lb(idx.degCal) = 0;
lb(idx.degCyc) = 0;
lb(idx.degPre) = 0;
lb(idx.degEnd) = 0;
lb(idx.Erep) = 0;
ub(idx.Erep) = cfg.E_max_kWh;
lb(idx.zRep) = 0;
ub(idx.zRep) = 1;
vtype(idx.zRep) = 'B';
if ~cfg.includeESSDegradationBasedReplacement
    ub(idx.Erep) = 0;
    ub(idx.zRep) = 0;
end

% 계약전력 bound
if cfg.optimizeContract
    lb(idx.Pcon) = cfg.contractMin_kW;
    ub(idx.Pcon) = cfg.contractMax_kW;

    % 계약전력 정수화
    % contractRoundingUnit_kW = 1일 때 P_contract 자체를 integer로 두면 된다.
    % 10 kW 단위 등으로 확장하려면 별도 정수변수 K를 두고 P_contract = unit*K로 구성해야 한다.
    if isfield(cfg, 'enforceIntegerContract') && cfg.enforceIntegerContract
        if isfield(cfg, 'contractRoundingUnit_kW') && abs(cfg.contractRoundingUnit_kW - 1) <= 1e-12
            vtype(idx.Pcon(:)) = 'I';
        else
            error('현재 코드는 optimizeContract에서 contractRoundingUnit_kW=1인 정수 계약전력만 직접 지원합니다.');
        end
    end
else
    fixedContractByYear = get_fixed_contract_by_year_revised(cfg, Y);
    lb(idx.Pcon(:)) = fixedContractByYear(:);
    ub(idx.Pcon(:)) = fixedContractByYear(:);
end

% 초과전력 변수
lb(idx.Pexc) = 0;
if strcmpi(cfg.contractMode, 'forbid')
    ub(idx.Pexc) = 0;
elseif strcmpi(cfg.contractMode, 'penalty')
    ub(idx.Pexc) = inf;
else
    error('cfg.contractMode는 forbid 또는 penalty이어야 합니다.');
end

% 수전설비 변수
lb(idx.facInst) = 0;
ub(idx.facInst) = cfg.facilityInstalledMax_kW;
lb(idx.facInc) = 0;

% 시간별 변수 bound
ub(idx.pCh(:)) = cfg.P_max_kW;
ub(idx.pDis(:)) = cfg.P_max_kW;

if cfg.useBinaryChargeDischarge
    vtype(idx.uCh(:)) = 'B';
    lb(idx.uCh(:)) = 0;
    ub(idx.uCh(:)) = 1;
end

% PV 변수 상한
if cfg.usePV
    for y = 1:Y
        pvY = data.pv_kW(:) * meta.pvMultiplier(y);
        ub(idx.pvUse(:,y)) = max(0, pvY);
        ub(idx.pvCurt(:,y)) = max(0, pvY);
    end
end

% ---------- ESS 미사용 시나리오 처리 ----------
% S0처럼 ESS를 설치하지 않는 경우 ESS/PCS, 충전/방전, SOC, 열화 관련 변수를 모두 0으로 고정한다.
% 이렇게 하면 동일한 모델 생성/해석 루틴으로 No-ESS 시나리오도 Gurobi에서 풀 수 있다.
if isfield(cfg, 'useESS') && ~cfg.useESS
    essFixedZeroVars = [idx.E(:); idx.Ppcs(:); idx.Einc(:); idx.Pinc(:); idx.Euse(:); ...
        idx.degBegin(:); idx.degCal(:); idx.degCyc(:); idx.degPre(:); idx.degEnd(:); idx.Erep(:); idx.zRep(:); ...
        idx.pCh(:); idx.pDis(:); idx.soc(:)];
    lb(essFixedZeroVars) = 0;
    ub(essFixedZeroVars) = 0;

    if cfg.useBinaryChargeDischarge
        lb(idx.uCh(:)) = 0;
        ub(idx.uCh(:)) = 0;
    end
end

% ---------- 목적함수 ----------
for y = 1:Y
    df = meta.discountFactor(y);
    priceY = data.price_KRW_per_kWh(:) * meta.energyPriceMultiplier(y);
    basicY = cfg.basicCharge_KRW_per_kW_month * meta.basicPriceMultiplier(y);

    % 전력량요금 현재가치
    obj(idx.pGrid(:,y)) = df * priceY * dt * data.yearScale;

    % binary 제거 시 불필요한 충방전 순환을 억제하기 위한 미소 패널티
    % 값이 너무 크면 ESS 운전을 왜곡하므로 0~1 원/kWh 수준에서만 사용한다.
    if isfield(cfg, 'smallCyclePenalty_KRW_per_kWh') && cfg.smallCyclePenalty_KRW_per_kWh > 0
        obj(idx.pCh(:,y))  = obj(idx.pCh(:,y))  + df * cfg.smallCyclePenalty_KRW_per_kWh * dt * data.yearScale;
        obj(idx.pDis(:,y)) = obj(idx.pDis(:,y)) + df * cfg.smallCyclePenalty_KRW_per_kWh * dt * data.yearScale;
    end

    % 기본요금 현재가치
    obj(idx.Pcon(y)) = obj(idx.Pcon(y)) + df * 12 * basicY;

    % 초과 penalty 현재가치
    if strcmpi(cfg.contractMode, 'penalty')
        obj(idx.Pexc(y)) = obj(idx.Pexc(y)) + df * cfg.penaltyExceed_KRW_per_kW_year;
    end

    % ESS/PCS 투자비는 증가분에만 부과한다.
    obj(idx.Einc(y)) = obj(idx.Einc(y)) + df * cfg.capexESS_KRW_per_kWh;
    obj(idx.Pinc(y)) = obj(idx.Pinc(y)) + df * cfg.capexPCS_KRW_per_kW;

    % 유지보수비 = 설치된 ESS+PCS 투자비의 cfg.omRateOfInstalledCost/year
    obj(idx.E(y)) = obj(idx.E(y)) + df * cfg.omRateOfInstalledCost * cfg.capexESS_KRW_per_kWh;
    obj(idx.Ppcs(y)) = obj(idx.Ppcs(y)) + df * cfg.omRateOfInstalledCost * cfg.capexPCS_KRW_per_kW;

    % ESS 교체비 현재가치: SOH 80% 도달 시 전체 ESS 교체 용량 Erep=E*zRep에 부과한다.
    if cfg.includeESSDegradationBasedReplacement
        obj(idx.Erep(y)) = obj(idx.Erep(y)) + df * cfg.replacementESS_KRW_per_kWh;
    end

    % PCS 교체비 현재가치: PCS 열화 모델은 없으므로 고정 수명 기준을 유지한다.
    if meta.replacementPCSFlag(y)
        obj(idx.Ppcs(y)) = obj(idx.Ppcs(y)) + df * cfg.replacementPCS_KRW_per_kW;
    end

    % 수전설비 증설비 현재가치
    obj(idx.facInc(y)) = obj(idx.facInc(y)) + df * cfg.facilityExpansionCost_KRW_per_kW;
end

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
        Ai = [Ai; repmat(row, numel(varIdx), 1)]; %#ok<AGROW>
        Aj = [Aj; varIdx]; %#ok<AGROW>
        Av = [Av; coeff]; %#ok<AGROW>
        rhs(row,1) = rhsVal; %#ok<AGROW>
        sense(1,row) = senseChar; %#ok<AGROW>
        constrnames{row,1} = cname; %#ok<AGROW>
    end

% ---------- 연도별 용량/설비 제약 ----------
for y = 1:Y
    % 필요 설비용량: facility_installed >= 1.2 * P_contract
    addrow([idx.facInst(y), idx.Pcon(y)], [1, -cfg.facilityMargin], '>', 0, sprintf('facility_ge_required_y%02d', y));

    % 첫 해 수전설비는 초기 설비보다 작아질 수 없다.
    if y == 1
        addrow(idx.facInst(y), 1, '>', cfg.initialFacilityCapacity_kW, 'facility_initial_lb');
        % facInc(1) >= facInst(1) - initialFacilityCapacity
        addrow([idx.facInst(y), idx.facInc(y)], [1, -1], '=', cfg.initialFacilityCapacity_kW, 'facility_increment_y01_exact');
    else
        % 설치 수전설비용량은 물리적으로 감소하지 않는다고 둔다.
        addrow([idx.facInst(y), idx.facInst(y-1)], [1, -1], '>', 0, sprintf('facility_nondecreasing_y%02d', y));
        % facInc(y) >= facInst(y) - facInst(y-1)
        addrow([idx.facInst(y), idx.facInst(y-1), idx.facInc(y)], [1, -1, -1], '=', 0, sprintf('facility_increment_y%02d_exact', y));
    end

    % ESS/PCS 설치 증가분 제약
    if y == 1
        if cfg.enforceNondecreasingESSCapacity
            addrow(idx.E(y), 1, '>', cfg.initialESSInstalled_kWh, 'E_initial_lb');
            addrow(idx.Ppcs(y), 1, '>', cfg.initialPCSInstalled_kW, 'P_initial_lb');
        end
        addrow([idx.E(y), idx.Einc(y)], [1, -1], '<', cfg.initialESSInstalled_kWh, 'E_increment_y01');
        addrow([idx.Ppcs(y), idx.Pinc(y)], [1, -1], '<', cfg.initialPCSInstalled_kW, 'P_increment_y01');
    else
        if cfg.enforceNondecreasingESSCapacity
            addrow([idx.E(y), idx.E(y-1)], [1, -1], '>', 0, sprintf('E_nondecreasing_y%02d', y));
            addrow([idx.Ppcs(y), idx.Ppcs(y-1)], [1, -1], '>', 0, sprintf('P_nondecreasing_y%02d', y));
        end
        addrow([idx.E(y), idx.E(y-1), idx.Einc(y)], [1, -1, -1], '<', 0, sprintf('E_increment_y%02d', y));
        addrow([idx.Ppcs(y), idx.Ppcs(y-1), idx.Pinc(y)], [1, -1, -1], '<', 0, sprintf('P_increment_y%02d', y));
    end

    % ---------- ESS 열화 상태 제약 ----------
    % 자연열화: degCal(y) = calendarRate * E_ESS(y)
    addrow([idx.degCal(y), idx.E(y)], [1, -cfg.calendarDegradationRate_per_year], '=', 0, sprintf('calendar_degradation_y%02d', y));

    % 연도 시작 누적 열화손실
    if y == 1
        addrow(idx.degBegin(y), 1, '=', cfg.initialESSDegradation_kWh, 'degradation_begin_y01');
    else
        % degBegin(y) = degEnd(y-1)
        addrow([idx.degBegin(y), idx.degEnd(y-1)], [1, -1], '=', 0, sprintf('degradation_carryover_y%02d', y));
    end

    % 교체 전 열화량: degPre(y) = degBegin(y) + degCal(y) + degCyc(y)
    addrow([idx.degPre(y), idx.degBegin(y), idx.degCal(y), idx.degCyc(y)], [1, -1, -1, -1], '=', 0, sprintf('degradation_pre_replace_y%02d', y));

    % ESS 교체 모델
    % zRep(y)=0: degEnd(y)=degPre(y), 교체비 없음.
    % zRep(y)=1: degEnd(y)=0, Erep(y)=E(y), 전체 ESS 교체비 발생.
    % replacementTriggerLossFraction=0.20이면 SOH 80% 도달/초과 시 교체가 강제된다.
    Mdeg = cfg.replacementBigM_kWh;
    Mrep = cfg.E_max_kWh;

    if cfg.includeESSDegradationBasedReplacement
        if ~isfield(cfg, 'enforceEOLCapacityLimit') || cfg.enforceEOLCapacityLimit
            % degPre <= trigger*E + M*zRep
            % 교체하지 않는 해(zRep=0)는 20% 손실 한계를 넘을 수 없다.
            % 한계를 넘기려면 zRep=1이 되어 연말 전체 교체가 발생한다.
            addrow([idx.degPre(y), idx.E(y), idx.zRep(y)], [1, -cfg.replacementTriggerLossFraction, -Mdeg], '<', 0, sprintf('degradation_trigger_with_replacement_y%02d', y));
        end

        % E가 0이면 replacement binary가 켜지지 않도록 방지한다.
        addrow([idx.E(y), idx.zRep(y)], [1, -cfg.minESSCapacityForReplacement_kWh], '>', 0, sprintf('replacement_requires_installed_ESS_y%02d', y));

        % degEnd = degPre*(1-zRep) 선형화
        % zRep=0 -> degEnd=degPre
        % zRep=1 -> degEnd=0
        addrow([idx.degEnd(y), idx.degPre(y)], [1, -1], '<', 0, sprintf('deg_end_le_pre_y%02d', y));
        addrow([idx.degEnd(y), idx.zRep(y)], [1, Mdeg], '<', Mdeg, sprintf('deg_end_zero_if_replace_y%02d', y));
        addrow([idx.degEnd(y), idx.degPre(y), idx.zRep(y)], [1, -1, Mdeg], '>', 0, sprintf('deg_end_ge_pre_if_no_replace_y%02d', y));

        % Erep = E*zRep 선형화
        % zRep=0 -> Erep=0
        % zRep=1 -> Erep=E
        addrow([idx.Erep(y), idx.E(y)], [1, -1], '<', 0, sprintf('Erep_le_E_y%02d', y));
        addrow([idx.Erep(y), idx.zRep(y)], [1, -Mrep], '<', 0, sprintf('Erep_le_Mz_y%02d', y));
        addrow([idx.Erep(y), idx.E(y), idx.zRep(y)], [1, -1, -Mrep], '>', -Mrep, sprintf('Erep_ge_E_if_replace_y%02d', y));
    else
        % 교체를 사용하지 않는 기준: 열화는 누적된다.
        addrow([idx.degEnd(y), idx.degPre(y)], [1, -1], '=', 0, sprintf('degradation_end_no_replacement_y%02d', y));
        if ~isfield(cfg, 'enforceEOLCapacityLimit') || cfg.enforceEOLCapacityLimit
            addrow([idx.degEnd(y), idx.E(y)], [1, -cfg.replacementTriggerLossFraction], '<', 0, sprintf('degradation_limit_no_replacement_y%02d', y));
        end
    end

    % 사용 가능 용량
    % 연도 y의 운전 가능 용량은 연초 누적 열화손실을 기준으로 계산한다.
    % 연말 교체가 발생하면 degEnd(y)=0이 되어 다음 해 degBegin(y+1)=0으로 이월된다.
    addrow([idx.Euse(y), idx.E(y), idx.degBegin(y)], [1, -1, 1], '=', 0, sprintf('usable_capacity_begin_year_y%02d', y));

    % ESS 지속시간 제약
    if cfg.enforceDuration
        addrow([idx.E(y), idx.Ppcs(y)], [1, -cfg.durationMin_h], '>', 0, sprintf('duration_min_y%02d', y));
        if isfinite(cfg.durationMax_h)
            addrow([idx.E(y), idx.Ppcs(y)], [1, -cfg.durationMax_h], '<', 0, sprintf('duration_max_y%02d', y));
        end
    end
end

% ---------- 시간별 운전 제약 ----------
for y = 1:Y
    loadY = data.load_kW(:) * meta.loadMultiplier(y);
    pvY = data.pv_kW(:) * meta.pvMultiplier(y);

    % 사이클 열화: degCyc(y) = alpha_cyc * sum_t(p_dis(t,y)*dt/etaDischarge) * yearScale
    % alpha_cyc = EOL 용량손실률 / EOL 등가사이클 수
    cycleAlpha = cfg.eolCapacityLossFraction / max(eps, cfg.cycleLife_EFC);
    cycleCoeff = -cycleAlpha * data.yearScale * dt / cfg.etaDischarge;
    addrow([idx.degCyc(y); idx.pDis(:,y)], [1; cycleCoeff * ones(T,1)], '=', 0, sprintf('cycle_degradation_y%02d', y));

    for t = 1:T
        % 전력수지
        % PV 미사용: p_grid - p_ch + p_dis = load
        % PV 사용  : p_grid - p_ch + p_dis + pv_use = load
        if cfg.usePV
            addrow([idx.pGrid(t,y), idx.pCh(t,y), idx.pDis(t,y), idx.pvUse(t,y)], [1, -1, 1, 1], '=', loadY(t), sprintf('power_balance_y%02d_t%04d', y, t));
            addrow([idx.pvUse(t,y), idx.pvCurt(t,y)], [1, 1], '=', pvY(t), sprintf('pv_balance_y%02d_t%04d', y, t));
        else
            addrow([idx.pGrid(t,y), idx.pCh(t,y), idx.pDis(t,y)], [1, -1, 1], '=', loadY(t), sprintf('power_balance_y%02d_t%04d', y, t));
        end

        % 충전/방전전력 <= 해당 연도 PCS 출력
        addrow([idx.pCh(t,y), idx.Ppcs(y)], [1, -1], '<', 0, sprintf('charge_le_pcs_y%02d_t%04d', y, t));
        addrow([idx.pDis(t,y), idx.Ppcs(y)], [1, -1], '<', 0, sprintf('discharge_le_pcs_y%02d_t%04d', y, t));

        % 충전/방전 동시 발생 방지
        if cfg.useBinaryChargeDischarge
            addrow([idx.pCh(t,y), idx.uCh(t,y)], [1, -cfg.P_max_kW], '<', 0, sprintf('charge_binary_y%02d_t%04d', y, t));
            addrow([idx.pDis(t,y), idx.uCh(t,y)], [1, cfg.P_max_kW], '<', cfg.P_max_kW, sprintf('discharge_binary_y%02d_t%04d', y, t));
        end

        % SOC 동역학
        if t == 1
            addrow([idx.soc(t,y), idx.Euse(y), idx.pCh(t,y), idx.pDis(t,y)], [1, -cfg.socInitial, -cfg.etaCharge*dt, dt/cfg.etaDischarge], '=', 0, sprintf('soc_dynamic_y%02d_t%04d', y, t));
        else
            addrow([idx.soc(t,y), idx.soc(t-1,y), idx.pCh(t,y), idx.pDis(t,y)], [1, -1, -cfg.etaCharge*dt, dt/cfg.etaDischarge], '=', 0, sprintf('soc_dynamic_y%02d_t%04d', y, t));
        end

        % SOC 범위
        addrow([idx.soc(t,y), idx.Euse(y)], [1, -cfg.socMax], '<', 0, sprintf('soc_upper_y%02d_t%04d', y, t));
        addrow([idx.soc(t,y), idx.Euse(y)], [-1, cfg.socMin], '<', 0, sprintf('soc_lower_y%02d_t%04d', y, t));

        % 계약전력 제약: p_grid <= P_contract + P_exceed
        addrow([idx.pGrid(t,y), idx.Pcon(y), idx.Pexc(y)], [1, -1, -1], '<', 0, sprintf('contract_limit_y%02d_t%04d', y, t));
    end

    % 최종 SOC 조건
    if cfg.enforceTerminalSOC
        addrow([idx.soc(T,y), idx.Euse(y)], [1, -cfg.socInitial], '=', 0, sprintf('terminal_soc_y%02d', y));
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
model.modelname = 'ESS_multiyear_capacity_operation_MILP';
model.varnames = varnames;
model.constrnames = constrnames;

meta.nvar = nvar;
meta.ncon = row;
meta.varnames = varnames;
meta.constrnames = constrnames;

fprintf('\n================ Model Summary ================\n');
fprintf('Years       : %d\n', Y);
fprintf('Hours/year  : %d\n', T);
fprintf('Variables   : %d\n', nvar);
fprintf('Constraints : %d\n', row);
fprintf('Binary vars : %d\n', sum(vtype == 'B'));
fprintf('Integer vars: %d\n', sum(vtype == 'I'));
fprintf('u_ch binary : %d\n', cfg.useBinaryChargeDischarge);
fprintf('ESS enabled : %d\n', cfg.useESS);
fprintf('PV enabled  : %d\n', cfg.usePV);
fprintf('Contract mode: %s\n', cfg.contractMode);
fprintf('Cost mode   : %s\n', cfg.costEvaluationMode);
fprintf('Optimization: %s\n', meta.optimizationType);
fprintf('ESS replacement model: SOH %.1f%% trigger, whole-ESS binary replacement=%d\n', 100*cfg.replacementAtSOH, cfg.includeESSDegradationBasedReplacement);

end

function tf = is_replacement_year(yearIndex, lifeYear)
% is_replacement_year
% ------------------------------------------------------------
% yearIndex는 1부터 시작한다. lifeYear=10이면 11년차 시작 시 교체비를 반영한다.
% ------------------------------------------------------------
if lifeYear <= 0
    tf = false;
    return;
end
elapsed = yearIndex - 1;
tf = elapsed > 0 && mod(elapsed, lifeYear) == 0;
end

%% ============================================================
%  Extract solution
% =============================================================
function sol = extract_solution_revised(x, idx, data, cfg, meta)
% extract_solution_revised
% ------------------------------------------------------------
% Gurobi solution vector를 해석 가능한 구조체 및 table로 변환한다.
% ------------------------------------------------------------

T = data.T;
Y = cfg.projectYears;
N = T * Y;

sol = struct();
sol.E_ESS_kWh = x(idx.E(:));
sol.P_PCS_kW = x(idx.Ppcs(:));
sol.P_contract_kW = x(idx.Pcon(:));
sol.P_exceed_kW = x(idx.Pexc(:));
sol.facility_installed_kW = x(idx.facInst(:));
sol.facility_required_kW = cfg.facilityMargin * sol.P_contract_kW;
sol.facility_expansion_kW = x(idx.facInc(:));
sol.E_ESS_increment_kWh = x(idx.Einc(:));
sol.P_PCS_increment_kW = x(idx.Pinc(:));

sol.E_usable_kWh = x(idx.Euse(:));
sol.degradation_begin_kWh = x(idx.degBegin(:));
sol.calendar_degradation_kWh = x(idx.degCal(:));
sol.cycle_degradation_kWh = x(idx.degCyc(:));
sol.degradation_pre_replace_kWh = x(idx.degPre(:));
sol.degradation_end_kWh = x(idx.degEnd(:));
sol.E_replacement_kWh = x(idx.Erep(:));
sol.z_replace_ESS = round(x(idx.zRep(:)));

sol.p_grid_kW = x(idx.pGrid);
sol.p_ch_kW = x(idx.pCh);
sol.p_dis_kW = x(idx.pDis);
sol.soc_kWh = x(idx.soc);

if cfg.useBinaryChargeDischarge
    sol.u_ch = x(idx.uCh);
else
    % binary를 사용하지 않는 완화 모델에서는 실제 충전전력으로 충전상태를 후처리한다.
    % 목적: Excel 검산 파일에서 충전이 발생하는데 U_ch=0으로 보이는 혼란을 방지한다.
    sol.u_ch = double(x(idx.pCh) > 1e-6);
end

% 수치 허용오차로 생기는 음수/미세 증설량을 출력 전에 정리한다.
sol = clean_solution_numerics_revised(sol, cfg);

if cfg.usePV
    sol.p_pv_use_kW = x(idx.pvUse);
    sol.p_pv_curt_kW = x(idx.pvCurt);
else
    sol.p_pv_use_kW = zeros(T,Y);
    sol.p_pv_curt_kW = zeros(T,Y);
end

% 다년도 dispatch table 생성
Year = zeros(N,1);
Timestamp = repmat(data.ts(:), Y, 1);
Load_kW = zeros(N,1);
PV_kW = zeros(N,1);
Price_KRW_per_kWh = zeros(N,1);
P_grid_kW = zeros(N,1);
P_ch_kW = zeros(N,1);
P_dis_kW = zeros(N,1);
SOC_kWh = zeros(N,1);
SOC_ratio = zeros(N,1);
E_ESS_kWh = zeros(N,1);
E_ESS_increment_kWh = zeros(N,1);
E_usable_kWh = zeros(N,1);
P_PCS_kW = zeros(N,1);
P_PCS_increment_kW = zeros(N,1);
P_contract_kW = zeros(N,1);
P_exceed_kW = zeros(N,1);
Degradation_begin_kWh = zeros(N,1);
Calendar_degradation_kWh = zeros(N,1);
Cycle_degradation_kWh = zeros(N,1);
Degradation_pre_replace_kWh = zeros(N,1);
Degradation_end_kWh = zeros(N,1);
Z_replace_ESS = zeros(N,1);
E_replacement_kWh = zeros(N,1);
U_ch = zeros(N,1);
P_pv_use_kW = zeros(N,1);
P_pv_curt_kW = zeros(N,1);
Simultaneous_charge_discharge_kW = zeros(N,1);

pos = 0;
for y = 1:Y
    r = (pos+1):(pos+T);
    Year(r) = y;
    Load_kW(r) = data.load_kW(:) * meta.loadMultiplier(y);
    PV_kW(r) = data.pv_kW(:) * meta.pvMultiplier(y);
    Price_KRW_per_kWh(r) = data.price_KRW_per_kWh(:) * meta.energyPriceMultiplier(y);
    P_grid_kW(r) = sol.p_grid_kW(:,y);
    P_ch_kW(r) = sol.p_ch_kW(:,y);
    P_dis_kW(r) = sol.p_dis_kW(:,y);
    SOC_kWh(r) = sol.soc_kWh(:,y);
    SOC_ratio(r) = sol.soc_kWh(:,y) ./ max(eps, sol.E_usable_kWh(y));
    E_ESS_kWh(r) = sol.E_ESS_kWh(y);
    E_ESS_increment_kWh(r) = sol.E_ESS_increment_kWh(y);
    E_usable_kWh(r) = sol.E_usable_kWh(y);
    P_PCS_kW(r) = sol.P_PCS_kW(y);
    P_PCS_increment_kW(r) = sol.P_PCS_increment_kW(y);
    P_contract_kW(r) = sol.P_contract_kW(y);
    P_exceed_kW(r) = sol.P_exceed_kW(y);
    Degradation_begin_kWh(r) = sol.degradation_begin_kWh(y);
    Calendar_degradation_kWh(r) = sol.calendar_degradation_kWh(y);
    Cycle_degradation_kWh(r) = sol.cycle_degradation_kWh(y);
    Degradation_pre_replace_kWh(r) = sol.degradation_pre_replace_kWh(y);
    Degradation_end_kWh(r) = sol.degradation_end_kWh(y);
    Z_replace_ESS(r) = sol.z_replace_ESS(y);
    E_replacement_kWh(r) = sol.E_replacement_kWh(y);
    U_ch(r) = sol.u_ch(:,y);
    P_pv_use_kW(r) = sol.p_pv_use_kW(:,y);
    P_pv_curt_kW(r) = sol.p_pv_curt_kW(:,y);
    Simultaneous_charge_discharge_kW(r) = min(sol.p_ch_kW(:,y), sol.p_dis_kW(:,y));
    pos = pos + T;
end

sol.dispatchTable = table(Year, Timestamp, Load_kW, PV_kW, Price_KRW_per_kWh, ...
    P_grid_kW, P_ch_kW, P_dis_kW, SOC_kWh, SOC_ratio, ...
    E_ESS_kWh, E_ESS_increment_kWh, E_usable_kWh, P_PCS_kW, P_PCS_increment_kW, ...
    P_contract_kW, P_exceed_kW, ...
    Degradation_begin_kWh, Calendar_degradation_kWh, Cycle_degradation_kWh, Degradation_pre_replace_kWh, ...
    Degradation_end_kWh, Z_replace_ESS, E_replacement_kWh, ...
    U_ch, P_pv_use_kW, P_pv_curt_kW, Simultaneous_charge_discharge_kW);

% 연도별 운전 진단
annual = table();
annual.year = (1:Y)';
annual.load_multiplier = meta.loadMultiplier;
annual.E_ESS_kWh = sol.E_ESS_kWh;
annual.E_usable_kWh = sol.E_usable_kWh;
annual.P_PCS_kW = sol.P_PCS_kW;
annual.P_contract_kW = sol.P_contract_kW;
annual.facility_required_kW = sol.facility_required_kW;
annual.facility_installed_kW = sol.facility_installed_kW;
annual.facility_expansion_kW = sol.facility_expansion_kW;
annual.P_grid_max_kW = max(sol.p_grid_kW, [], 1)';
annual.load_peak_kW = zeros(Y,1);
annual.noess_grid_peak_kW = zeros(Y,1);
annual.peak_reduction_raw_kW = zeros(Y,1);
annual.peak_reduction_kW = zeros(Y,1);
annual.charge_energy_kWh = zeros(Y,1);
annual.discharge_energy_kWh = zeros(Y,1);
annual.battery_discharge_energy_kWh = zeros(Y,1);
annual.equivalent_cycles = zeros(Y,1);
annual.simultaneous_power_max_kW = zeros(Y,1);
annual.simultaneous_energy_kWh = zeros(Y,1);
annual.simultaneous_hour_count = zeros(Y,1);
annual.SOC_min_kWh = min(sol.soc_kWh, [], 1)';
annual.SOC_max_kWh = max(sol.soc_kWh, [], 1)';
annual.SOC_min_ratio = zeros(Y,1);
annual.SOC_max_ratio = zeros(Y,1);
annual.calendar_degradation_kWh = sol.calendar_degradation_kWh;
annual.cycle_degradation_kWh = sol.cycle_degradation_kWh;
annual.degradation_begin_kWh = sol.degradation_begin_kWh;
annual.degradation_pre_replace_kWh = sol.degradation_pre_replace_kWh;
annual.degradation_end_kWh = sol.degradation_end_kWh;
annual.z_replace_ESS = sol.z_replace_ESS;
annual.E_replacement_kWh = sol.E_replacement_kWh;
annual.calendar_degradation_fraction = zeros(Y,1);
annual.cycle_degradation_fraction = zeros(Y,1);
annual.cumulative_degradation_fraction = zeros(Y,1);
annual.usable_capacity_fraction = zeros(Y,1);

for y = 1:Y
    loadY = data.load_kW(:) * meta.loadMultiplier(y);
    pvY = data.pv_kW(:) * meta.pvMultiplier(y);
    if cfg.usePV
        gridNoEss = max(loadY - pvY, 0);
    else
        gridNoEss = loadY;
    end

    annual.load_peak_kW(y) = max(loadY);
    annual.noess_grid_peak_kW(y) = max(gridNoEss);
    annual.peak_reduction_raw_kW(y) = annual.noess_grid_peak_kW(y) - annual.P_grid_max_kW(y);
    annual.peak_reduction_kW(y) = max(0, annual.peak_reduction_raw_kW(y));
    annual.charge_energy_kWh(y) = sum(sol.p_ch_kW(:,y) * data.dt_h) * data.yearScale;
    annual.discharge_energy_kWh(y) = sum(sol.p_dis_kW(:,y) * data.dt_h) * data.yearScale;
    annual.battery_discharge_energy_kWh(y) = sum(sol.p_dis_kW(:,y) * data.dt_h / cfg.etaDischarge) * data.yearScale;

    simul_kW_y = min(sol.p_ch_kW(:,y), sol.p_dis_kW(:,y));
    annual.simultaneous_power_max_kW(y) = max(simul_kW_y);
    annual.simultaneous_energy_kWh(y) = sum(simul_kW_y * data.dt_h) * data.yearScale;
    annual.simultaneous_hour_count(y) = sum(simul_kW_y > 1e-6);

    if sol.E_ESS_kWh(y) > 1e-6
        annual.equivalent_cycles(y) = annual.battery_discharge_energy_kWh(y) / sol.E_ESS_kWh(y);
        annual.calendar_degradation_fraction(y) = sol.calendar_degradation_kWh(y) / sol.E_ESS_kWh(y);
        annual.cycle_degradation_fraction(y) = sol.cycle_degradation_kWh(y) / sol.E_ESS_kWh(y);
        annual.cumulative_degradation_fraction(y) = sol.degradation_end_kWh(y) / sol.E_ESS_kWh(y);
        annual.usable_capacity_fraction(y) = sol.E_usable_kWh(y) / sol.E_ESS_kWh(y);
    else
        annual.equivalent_cycles(y) = 0;
        annual.calendar_degradation_fraction(y) = 0;
        annual.cycle_degradation_fraction(y) = 0;
        annual.cumulative_degradation_fraction(y) = 0;
        annual.usable_capacity_fraction(y) = 0;
    end

    if sol.E_usable_kWh(y) > 1e-6
        annual.SOC_min_ratio(y) = annual.SOC_min_kWh(y) / sol.E_usable_kWh(y);
        annual.SOC_max_ratio(y) = annual.SOC_max_kWh(y) / sol.E_usable_kWh(y);
    else
        annual.SOC_min_ratio(y) = 0;
        annual.SOC_max_ratio(y) = 0;
    end
end

sol.annualTable = annual;

end

function sol = clean_solution_numerics_revised(sol, cfg)
% clean_solution_numerics_revised
% ------------------------------------------------------------
% Gurobi 허용오차로 생기는 미세 음수, 미세 증설량, 비정수 계약전력 표시값을 정리한다.
% 특히 S2에서 ESS=0인데 수전설비 증설비만 수만 원 차이 나는 문제를 방지하기 위해
% facility_required/installed/expansion을 계약전력으로부터 결정론적으로 재계산한다.
% ------------------------------------------------------------

tol = 1e-7;

fieldsVec = {'E_ESS_kWh','P_PCS_kW','P_contract_kW','P_exceed_kW','E_ESS_increment_kWh','P_PCS_increment_kW', ...
    'E_usable_kWh','degradation_begin_kWh','calendar_degradation_kWh','cycle_degradation_kWh','degradation_pre_replace_kWh', ...
    'degradation_end_kWh','E_replacement_kWh'};
for k = 1:numel(fieldsVec)
    f = fieldsVec{k};
    if isfield(sol, f)
        v = sol.(f);
        v(abs(v) < tol) = 0;
        sol.(f) = v;
    end
end

fieldsMat = {'p_grid_kW','p_ch_kW','p_dis_kW','soc_kWh','u_ch'};
for k = 1:numel(fieldsMat)
    f = fieldsMat{k};
    if isfield(sol, f)
        v = sol.(f);
        v(abs(v) < tol) = 0;
        sol.(f) = v;
    end
end

% 계약전력 정수화 표시 보정. 모델에서 integer로 푼 경우에도 4772.999999처럼 출력될 수 있다.
if isfield(cfg, 'enforceIntegerContract') && cfg.enforceIntegerContract && ...
        isfield(cfg, 'contractRoundingUnit_kW') && cfg.contractRoundingUnit_kW > 0
    unit = cfg.contractRoundingUnit_kW;
    rounded = round(sol.P_contract_kW / unit) * unit;
    if max(abs(rounded - sol.P_contract_kW)) <= 1e-5 * max(1, unit)
        sol.P_contract_kW = rounded;
    end
end

% 수전설비는 계약전력의 1.2배 필요용량과 기존 설치용량의 누적 최대값으로 후처리한다.
% 이는 모델 목적함수의 허용오차로 인한 미세 증설비 차이를 제거하기 위한 출력/비용 재계산 기준이다.
Y = numel(sol.P_contract_kW);
sol.facility_required_kW = cfg.facilityMargin * sol.P_contract_kW(:);
sol.facility_installed_kW = zeros(Y,1);
sol.facility_expansion_kW = zeros(Y,1);
prevFacility = cfg.initialFacilityCapacity_kW;
for y = 1:Y
    required = sol.facility_required_kW(y);
    installed = max(prevFacility, required);
    inc = max(0, installed - prevFacility);
    if abs(inc) < 1e-6
        inc = 0;
    end
    sol.facility_installed_kW(y) = installed;
    sol.facility_expansion_kW(y) = inc;
    prevFacility = installed;
end

end

%% ============================================================
%  Cost breakdown
% =============================================================
function cost = compute_cost_breakdown_revised(sol, data, cfg, meta)
% compute_cost_breakdown_revised
% ------------------------------------------------------------
% 목적함수 구성요소별 현재가치 비용을 계산한다.
% ------------------------------------------------------------

Y = cfg.projectYears;
dt = data.dt_h;
H = data.yearScale;

costTable = table();
costTable.year = (1:Y)';
costTable.discount_factor = meta.discountFactor;
costTable.energy_cost_PV_KRW = zeros(Y,1);
costTable.basic_cost_PV_KRW = zeros(Y,1);
costTable.exceed_cost_PV_KRW = zeros(Y,1);
costTable.ess_capex_PV_KRW = zeros(Y,1);
costTable.pcs_capex_PV_KRW = zeros(Y,1);
costTable.om_cost_PV_KRW = zeros(Y,1);
costTable.replacement_cost_PV_KRW = zeros(Y,1);
costTable.facility_expansion_cost_PV_KRW = zeros(Y,1);
costTable.stabilization_penalty_PV_KRW = zeros(Y,1);
costTable.total_cost_PV_KRW = zeros(Y,1);

for y = 1:Y
    df = meta.discountFactor(y);
    priceY = data.price_KRW_per_kWh(:) * meta.energyPriceMultiplier(y);
    basicY = cfg.basicCharge_KRW_per_kW_month * meta.basicPriceMultiplier(y);

    costTable.energy_cost_PV_KRW(y) = df * H * sum(priceY .* sol.p_grid_kW(:,y) * dt);
    costTable.basic_cost_PV_KRW(y) = df * 12 * basicY * sol.P_contract_kW(y);

    if strcmpi(cfg.contractMode, 'penalty')
        costTable.exceed_cost_PV_KRW(y) = df * cfg.penaltyExceed_KRW_per_kW_year * sol.P_exceed_kW(y);
    end

    costTable.ess_capex_PV_KRW(y) = df * cfg.capexESS_KRW_per_kWh * sol.E_ESS_increment_kWh(y);
    costTable.pcs_capex_PV_KRW(y) = df * cfg.capexPCS_KRW_per_kW * sol.P_PCS_increment_kW(y);

    costTable.om_cost_PV_KRW(y) = df * cfg.omRateOfInstalledCost * ...
        (cfg.capexESS_KRW_per_kWh * sol.E_ESS_kWh(y) + cfg.capexPCS_KRW_per_kW * sol.P_PCS_kW(y));

    if cfg.includeESSDegradationBasedReplacement
        costTable.replacement_cost_PV_KRW(y) = costTable.replacement_cost_PV_KRW(y) + df * cfg.replacementESS_KRW_per_kWh * sol.E_replacement_kWh(y);
    end
    if meta.replacementPCSFlag(y)
        costTable.replacement_cost_PV_KRW(y) = costTable.replacement_cost_PV_KRW(y) + df * cfg.replacementPCS_KRW_per_kW * sol.P_PCS_kW(y);
    end

    costTable.facility_expansion_cost_PV_KRW(y) = df * cfg.facilityExpansionCost_KRW_per_kW * sol.facility_expansion_kW(y);

    if isfield(cfg, 'smallCyclePenalty_KRW_per_kWh') && cfg.smallCyclePenalty_KRW_per_kWh > 0
        costTable.stabilization_penalty_PV_KRW(y) = df * cfg.smallCyclePenalty_KRW_per_kWh * H * ...
            sum((sol.p_ch_kW(:,y) + sol.p_dis_kW(:,y)) * dt);
    end

    costTable.total_cost_PV_KRW(y) = costTable.energy_cost_PV_KRW(y) + costTable.basic_cost_PV_KRW(y) + ...
        costTable.exceed_cost_PV_KRW(y) + costTable.ess_capex_PV_KRW(y) + costTable.pcs_capex_PV_KRW(y) + ...
        costTable.om_cost_PV_KRW(y) + costTable.replacement_cost_PV_KRW(y) + costTable.facility_expansion_cost_PV_KRW(y) + ...
        costTable.stabilization_penalty_PV_KRW(y);
end

cost = struct();
cost.table = costTable;
cost.energyCostPV = sum(costTable.energy_cost_PV_KRW);
cost.basicCostPV = sum(costTable.basic_cost_PV_KRW);
cost.exceedCostPV = sum(costTable.exceed_cost_PV_KRW);
cost.essCapexPV = sum(costTable.ess_capex_PV_KRW);
cost.pcsCapexPV = sum(costTable.pcs_capex_PV_KRW);
cost.omCostPV = sum(costTable.om_cost_PV_KRW);
cost.replacementCostPV = sum(costTable.replacement_cost_PV_KRW);
cost.facilityExpansionCostPV = sum(costTable.facility_expansion_cost_PV_KRW);
cost.stabilizationPenaltyPV = sum(costTable.stabilization_penalty_PV_KRW);
cost.totalPresentValue = sum(costTable.total_cost_PV_KRW);
cost.operationCostPV = cost.energyCostPV + cost.basicCostPV + cost.exceedCostPV;
cost.designCostPV = cost.essCapexPV + cost.pcsCapexPV + cost.omCostPV + cost.replacementCostPV + cost.facilityExpansionCostPV;
cost.regularizationCostPV = cost.stabilizationPenaltyPV;

% 주요 지표용 요약 table
cost.summaryTable = table( ...
    cost.energyCostPV, cost.basicCostPV, cost.exceedCostPV, cost.essCapexPV, cost.pcsCapexPV, ...
    cost.omCostPV, cost.replacementCostPV, cost.facilityExpansionCostPV, cost.stabilizationPenaltyPV, cost.designCostPV, cost.totalPresentValue, ...
    'VariableNames', {'energyCostPV_KRW','basicCostPV_KRW','exceedCostPV_KRW','essCapexPV_KRW','pcsCapexPV_KRW', ...
    'omCostPV_KRW','replacementCostPV_KRW','facilityExpansionCostPV_KRW','stabilizationPenaltyPV_KRW','designCostPV_KRW','totalPresentValue_KRW'});

end

%% ============================================================
%  No-ESS baseline
% =============================================================
function noess = compute_noess_baseline_revised(data, cfg, meta)
% compute_noess_baseline_revised
% ------------------------------------------------------------
% ESS 미설치 기준의 다년도 비용을 계산한다.
% 기본 비교용이며, penalty 모드의 계약전력 최적화까지 엄밀히 푸는 별도 LP는 아니다.
% ------------------------------------------------------------

Y = cfg.projectYears;
dt = data.dt_h;
H = data.yearScale;
fixedContractByYear = get_fixed_contract_by_year_revised(cfg, Y);

base = table();
base.year = (1:Y)';
base.grid_peak_kW = zeros(Y,1);
base.P_contract_kW = zeros(Y,1);
base.P_exceed_kW = zeros(Y,1);
base.facility_required_kW = zeros(Y,1);
base.facility_installed_kW = zeros(Y,1);
base.facility_expansion_kW = zeros(Y,1);
base.energy_cost_PV_KRW = zeros(Y,1);
base.basic_cost_PV_KRW = zeros(Y,1);
base.exceed_cost_PV_KRW = zeros(Y,1);
base.facility_expansion_cost_PV_KRW = zeros(Y,1);
base.total_cost_PV_KRW = zeros(Y,1);
base.feasible_under_forbid = true(Y,1);

prevFacility = cfg.initialFacilityCapacity_kW;

for y = 1:Y
    df = meta.discountFactor(y);
    loadY = data.load_kW(:) * meta.loadMultiplier(y);
    pvY = data.pv_kW(:) * meta.pvMultiplier(y);
    priceY = data.price_KRW_per_kWh(:) * meta.energyPriceMultiplier(y);
    basicY = cfg.basicCharge_KRW_per_kW_month * meta.basicPriceMultiplier(y);

    if cfg.usePV
        grid0 = max(loadY - pvY, 0);
    else
        grid0 = loadY;
    end

    peak0 = max(grid0);

    if cfg.optimizeContract
        Pcon0 = max(cfg.contractMin_kW, min(peak0, cfg.contractMax_kW));
    else
        Pcon0 = fixedContractByYear(y);
    end

    Pexc0 = max(0, peak0 - Pcon0);
    if strcmpi(cfg.contractMode, 'forbid') && Pexc0 > 1e-6
        base.feasible_under_forbid(y) = false;
    end

    requiredFacility = cfg.facilityMargin * Pcon0;
    installedFacility = max(prevFacility, requiredFacility);
    facilityInc = max(0, installedFacility - prevFacility);
    prevFacility = installedFacility;

    base.grid_peak_kW(y) = peak0;
    base.P_contract_kW(y) = Pcon0;
    base.P_exceed_kW(y) = Pexc0;
    base.facility_required_kW(y) = requiredFacility;
    base.facility_installed_kW(y) = installedFacility;
    base.facility_expansion_kW(y) = facilityInc;
    base.energy_cost_PV_KRW(y) = df * H * sum(priceY .* grid0 * dt);
    base.basic_cost_PV_KRW(y) = df * 12 * basicY * Pcon0;
    if strcmpi(cfg.contractMode, 'penalty')
        base.exceed_cost_PV_KRW(y) = df * cfg.penaltyExceed_KRW_per_kW_year * Pexc0;
    end
    base.facility_expansion_cost_PV_KRW(y) = df * cfg.facilityExpansionCost_KRW_per_kW * facilityInc;
    base.total_cost_PV_KRW(y) = base.energy_cost_PV_KRW(y) + base.basic_cost_PV_KRW(y) + base.exceed_cost_PV_KRW(y) + base.facility_expansion_cost_PV_KRW(y);
end

noess = struct();
noess.table = base;
noess.energyCostPV = sum(base.energy_cost_PV_KRW);
noess.basicCostPV = sum(base.basic_cost_PV_KRW);
noess.exceedCostPV = sum(base.exceed_cost_PV_KRW);
noess.facilityExpansionCostPV = sum(base.facility_expansion_cost_PV_KRW);
noess.totalPresentValue = sum(base.total_cost_PV_KRW);
noess.feasibleUnderForbid = all(base.feasible_under_forbid);

end

%% ============================================================
%  Reports
% =============================================================
function report_solution_revised(sol, cost, noess, cfg, data, meta)
% report_solution_revised
% ------------------------------------------------------------
% 최적화 결과 요약 출력
% ------------------------------------------------------------

Y = cfg.projectYears;
lastYear = Y;

fprintf('\n================ Final-Year Optimal Design ================\n');
fprintf('E_ESS(y%d)              : %s\n', lastYear, fmt_unit(sol.E_ESS_kWh(lastYear), 3, 'kWh'));
fprintf('E_usable(y%d)           : %s\n', lastYear, fmt_unit(sol.E_usable_kWh(lastYear), 3, 'kWh'));
fprintf('Deg_end(y%d)            : %s\n', lastYear, fmt_unit(sol.degradation_end_kWh(lastYear), 3, 'kWh'));
fprintf('P_PCS(y%d)              : %s\n', lastYear, fmt_unit(sol.P_PCS_kW(lastYear), 3, 'kW'));
fprintf('P_contract(y%d)         : %s\n', lastYear, fmt_unit(sol.P_contract_kW(lastYear), 3, 'kW'));
fprintf('Required facility(y%d)  : %s\n', lastYear, fmt_unit(sol.facility_required_kW(lastYear), 3, 'kW'));
fprintf('Installed facility(y%d) : %s\n', lastYear, fmt_unit(sol.facility_installed_kW(lastYear), 3, 'kW'));
fprintf('P_grid max(y%d)         : %s\n', lastYear, fmt_unit(sol.annualTable.P_grid_max_kW(lastYear), 3, 'kW'));

fprintf('\n================ Present Value Cost Breakdown ================\n');
print_cost_line('전력량요금 현재가치', cost.energyCostPV);
print_cost_line('기본요금 현재가치', cost.basicCostPV);
print_cost_line('계약전력 초과비용 현재가치', cost.exceedCostPV);
print_cost_line('ESS 투자비 현재가치', cost.essCapexPV);
print_cost_line('PCS 투자비 현재가치', cost.pcsCapexPV);
print_cost_line('유지보수비 현재가치', cost.omCostPV);
print_cost_line('교체비 현재가치', cost.replacementCostPV);
print_cost_line('수전설비 증설비 현재가치', cost.facilityExpansionCostPV);
if isfield(cost, 'stabilizationPenaltyPV')
    print_cost_line('충방전 안정화 패널티 현재가치', cost.stabilizationPenaltyPV);
end
print_cost_line('설비 관련 비용 현재가치', cost.designCostPV);
print_cost_line('총비용 현재가치', cost.totalPresentValue);

fprintf('\n================ No-ESS Baseline ================\n');
print_cost_line('No-ESS 전력량요금 현재가치', noess.energyCostPV);
print_cost_line('No-ESS 기본요금 현재가치', noess.basicCostPV);
print_cost_line('No-ESS 초과비용 현재가치', noess.exceedCostPV);
print_cost_line('No-ESS 수전설비 증설비 현재가치', noess.facilityExpansionCostPV);
print_cost_line('No-ESS 총비용 현재가치', noess.totalPresentValue);

if ~noess.feasibleUnderForbid
    fprintf('[WARN] No-ESS 기준은 일부 연도에서 forbid 조건을 만족하지 못합니다.\n');
end

operationSavingPV = (noess.energyCostPV + noess.basicCostPV + noess.exceedCostPV) - cost.operationCostPV;
netSavingPV = noess.totalPresentValue - cost.totalPresentValue;

fprintf('\n================ Economic Comparison ================\n');
print_cost_line('설비비 제외 절감액 현재가치', operationSavingPV);
print_cost_line('설비비 포함 순절감액 현재가치', netSavingPV);

fprintf('\n================ Annual Operation Summary ================\n');
fprintf('%4s %12s %12s %12s %12s %12s %12s %12s %12s %12s\n', 'Year', 'E[kWh]', 'Euse[kWh]', 'PCS[kW]', 'Pcon[kW]', 'PgridMax', 'PeakRed', 'EFC', 'DegEnd', 'Erep');
for y = 1:Y
    fprintf('%4d %12s %12s %12s %12s %12s %12s %12s %12s %12s\n', ...
        y, ...
        fmt_real(sol.annualTable.E_ESS_kWh(y), 2), ...
        fmt_real(sol.annualTable.E_usable_kWh(y), 2), ...
        fmt_real(sol.annualTable.P_PCS_kW(y), 2), ...
        fmt_real(sol.annualTable.P_contract_kW(y), 2), ...
        fmt_real(sol.annualTable.P_grid_max_kW(y), 2), ...
        fmt_real(sol.annualTable.peak_reduction_kW(y), 2), ...
        fmt_real(sol.annualTable.equivalent_cycles(y), 2), ...
        fmt_real(sol.annualTable.cumulative_degradation_fraction(y), 6), ...
        fmt_real(sol.annualTable.E_replacement_kWh(y), 2));
end

fprintf('\n================ Diagnostic Values ================\n');
fprintf('Load growth rate              : %s%%/year\n', fmt_real(100*cfg.loadGrowthRate, 3));
fprintf('Facility margin               : %s\n', fmt_real(cfg.facilityMargin, 3));
fprintf('O&M rate                      : %s%% of ESS+PCS capex/year\n', fmt_real(100*cfg.omRateOfInstalledCost, 3));
fprintf('Calendar degradation rate     : %s%%/year\n', fmt_real(100*cfg.calendarDegradationRate_per_year, 3));
fprintf('Cycle degradation coefficient : %s capacity-loss fraction/EFC\n', fmt_real(cfg.eolCapacityLossFraction / max(eps, cfg.cycleLife_EFC), 10));
fprintf('Replacement trigger loss      : %s%%\n', fmt_real(100*cfg.replacementTriggerLossFraction, 3));
fprintf('Cost evaluation               : %s\n', cfg.costEvaluationMode);
fprintf('Year scale                    : %s\n', fmt_real(data.yearScale, 6));
fprintf('Discount rate                 : %s%%\n', fmt_real(100*cfg.discountRate, 3));

% 충방전 동시 발생 검증
simul_kW = min(sol.p_ch_kW(:), sol.p_dis_kW(:));
maxSimul_kW = max(simul_kW);
sumSimul_kWh = sum(simul_kW) * data.dt_h * data.yearScale;
numSimulHours = sum(simul_kW > 1e-6);
totalCh_kWh = sum(sol.p_ch_kW(:)) * data.dt_h * data.yearScale;
totalDis_kWh = sum(sol.p_dis_kW(:)) * data.dt_h * data.yearScale;
if totalCh_kWh + totalDis_kWh > 0
    simulRatio = sumSimul_kWh / (0.5 * (totalCh_kWh + totalDis_kWh));
else
    simulRatio = 0;
end
fprintf('Simultaneous charge/discharge max  : %s kW\n', fmt_real(maxSimul_kW, 9));
fprintf('Simultaneous charge/discharge hours: %d h\n', numSimulHours);
fprintf('Simultaneous charge/discharge sum  : %s kWh\n', fmt_real(sumSimul_kWh, 9));
fprintf('Simultaneous charge/discharge ratio: %s\n', fmt_real(simulRatio, 9));
if ~cfg.useBinaryChargeDischarge && maxSimul_kW > 1e-3
    fprintf('[WARN] u_ch binary가 꺼진 상태에서 유의미한 동시 충방전이 발생했습니다. 이 결과는 논문 최종값으로 사용하면 안 됩니다.\n');
end

fprintf('\n================ Required Indicators ================\n');
fprintf('ESS 용량 [kWh]        : final year %s\n', fmt_unit(sol.E_ESS_kWh(end), 3, 'kWh'));
fprintf('열화반영 ESS 용량 [kWh]: final year %s\n', fmt_unit(sol.E_usable_kWh(end), 3, 'kWh'));
fprintf('누적 열화손실 [kWh]   : final year %s\n', fmt_unit(sol.degradation_end_kWh(end), 3, 'kWh'));
fprintf('열화기반 교체량 [kWh] : total %s\n', fmt_unit(sum(sol.E_replacement_kWh), 3, 'kWh'));
fprintf('PCS 출력 [kW]         : final year %s\n', fmt_unit(sol.P_PCS_kW(end), 3, 'kW'));
fprintf('전력량요금 [원]       : %s\n', fmt_krw(cost.energyCostPV));
fprintf('기본요금 [원]         : %s\n', fmt_krw(cost.basicCostPV));
fprintf('총비용 [원]           : %s\n', fmt_krw(cost.totalPresentValue));
fprintf('SOC 최적값 [kWh]      : final year min/max %s / %s\n', fmt_unit(min(sol.soc_kWh(:,end)), 3, 'kWh'), fmt_unit(max(sol.soc_kWh(:,end)), 3, 'kWh'));
fprintf('P_grid^max [kW]       : final year %s\n', fmt_unit(sol.annualTable.P_grid_max_kW(end), 3, 'kW'));
fprintf('피크 저감량 [kW]      : final year %s\n', fmt_unit(sol.annualTable.peak_reduction_kW(end), 3, 'kW'));
fprintf('충전량/방전량 [kWh]   : final year %s / %s\n', fmt_unit(sol.annualTable.charge_energy_kWh(end), 3, 'kWh'), fmt_unit(sol.annualTable.discharge_energy_kWh(end), 3, 'kWh'));
fprintf('등가 사이클 [cycle/y] : final year %s\n', fmt_unit(sol.annualTable.equivalent_cycles(end), 3, 'cycle/year'));
fprintf('SOC 범위              : final year %s - %s\n', fmt_real(sol.annualTable.SOC_min_ratio(end), 4), fmt_real(sol.annualTable.SOC_max_ratio(end), 4));
fprintf('설비비 제외 절감액    : %s\n', fmt_krw(operationSavingPV));
fprintf('설비비 포함 순절감액  : %s\n', fmt_krw(netSavingPV));

end

%% ============================================================
%  Upper-bound diagnostics
% =============================================================
function diagnose_upper_bound_solution_revised(sol, cost, noess, cfg, data)
% diagnose_upper_bound_solution_revised
% ------------------------------------------------------------
% ESS 용량 또는 PCS 출력이 상한값으로 나오는 경우 원인 진단
% ------------------------------------------------------------

tolE = max(1e-5, 1e-6 * max(1, cfg.E_max_kWh));
tolP = max(1e-5, 1e-6 * max(1, cfg.P_max_kW));

hitE = sol.E_ESS_kWh >= cfg.E_max_kWh - tolE;
hitP = sol.P_PCS_kW >= cfg.P_max_kW - tolP;

fprintf('\n================ Bound Diagnostic ================\n');

if ~any(hitE) && ~any(hitP)
    fprintf('ESS 용량/PCS 출력 모두 상한에 걸리지 않았습니다.\n');
else
    if any(hitE)
        years = find(hitE);
        fprintf('[WARN] E_ESS가 상한값에 도달한 연도: %s\n', mat2str(years(:)'));
    end
    if any(hitP)
        years = find(hitP);
        fprintf('[WARN] P_PCS가 상한값에 도달한 연도: %s\n', mat2str(years(:)'));
    end
end

fprintf('Max E_ESS / E_max ratio : %s%%\n', fmt_real(100 * max(sol.E_ESS_kWh) / cfg.E_max_kWh, 2));
fprintf('Max P_PCS / P_max ratio : %s%%\n', fmt_real(100 * max(sol.P_PCS_kW) / cfg.P_max_kW, 2));
fprintf('Max load in final year  : %s\n', fmt_unit(max(data.load_kW) * (1 + cfg.loadGrowthRate)^(cfg.projectYears-1), 3, 'kW'));

operationSavingPV = (noess.energyCostPV + noess.basicCostPV + noess.exceedCostPV) - cost.operationCostPV;
netSavingPV = noess.totalPresentValue - cost.totalPresentValue;
print_cost_line('설비비 제외 절감액 현재가치', operationSavingPV);
print_cost_line('설비비 포함 순절감액 현재가치', netSavingPV);

% 최종 연도 기준 binding 진단
y = cfg.projectYears;
socUpperHit = mean(abs(sol.soc_kWh(:,y) - cfg.socMax * sol.E_usable_kWh(y)) <= 1e-4 * max(1, sol.E_usable_kWh(y)));
socLowerHit = mean(abs(sol.soc_kWh(:,y) - cfg.socMin * sol.E_usable_kWh(y)) <= 1e-4 * max(1, sol.E_usable_kWh(y)));
pcsChargeHit = mean(abs(sol.p_ch_kW(:,y) - sol.P_PCS_kW(y)) <= 1e-4 * max(1, sol.P_PCS_kW(y)));
pcsDisHit = mean(abs(sol.p_dis_kW(:,y) - sol.P_PCS_kW(y)) <= 1e-4 * max(1, sol.P_PCS_kW(y)));

fprintf('Final-year SOC upper hit ratio       : %s\n', fmt_real(socUpperHit, 3));
fprintf('Final-year SOC lower hit ratio       : %s\n', fmt_real(socLowerHit, 3));
fprintf('Final-year PCS charge binding ratio  : %s\n', fmt_real(pcsChargeHit, 3));
fprintf('Final-year PCS discharge binding ratio: %s\n', fmt_real(pcsDisHit, 3));

if any(hitE) || any(hitP)
    fprintf('\n[진단 해석]\n');
    fprintf('- 상한 도달은 반드시 좋은 결과가 아니다. E_max_kWh 또는 P_max_kW가 실제 최적보다 낮거나, 투자비/유지보수비/증설비 단가가 과소 설정되었을 가능성이 있다.\n');
    fprintf('- loadGrowthRate가 높고 contractMin_kW가 낮으면 ESS가 계약전력 절감을 과도하게 담당할 수 있다.\n');
    fprintf('- capexESS, capexPCS, omRateOfInstalledCost, facilityExpansionCost_KRW_per_kW 민감도 분석이 필요하다.\n');
end

end

%% ============================================================
%  Infeasibility diagnostics
% =============================================================
function diagnose_infeasible_model_revised(model, meta, cfg)
% diagnose_infeasible_model_revised
% ------------------------------------------------------------
% Gurobi IIS를 이용해 infeasible 원인 후보를 출력한다.
% ------------------------------------------------------------

fprintf('\n================ Infeasibility Diagnostic ================\n');

try
    gurobi_write(model, 'infeasible_debug_model_revised.lp');
    fprintf('[INFO] Infeasible debug model written: infeasible_debug_model_revised.lp\n');
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
    fprintf('1) forbid 모드에서 contractMax_kW와 P_max_kW가 너무 낮음\n');
    fprintf('2) E_max_kWh 또는 P_max_kW가 부하 증가율 적용 후 필요량보다 낮음\n');
    fprintf('3) facilityInstalledMax_kW가 1.2*P_contract를 수용하지 못함\n');
    fprintf('4) durationMin_h, durationMax_h가 과도하게 빡빡함\n');
    fprintf('5) terminal SOC 조건과 마지막 시간대 운전이 충돌\n');
    fprintf('6) 초기 설비용량, 기존 ESS/PCS 용량 설정이 bound와 충돌\n');

    fprintf('\n[현재 주요 설정]\n');
    fprintf('contractMode              : %s\n', cfg.contractMode);
    fprintf('optimizeContract          : %d\n', cfg.optimizeContract);
    fixedVecDiag = get_fixed_contract_by_year_revised(cfg, cfg.projectYears);
    fprintf('contractFixedMode         : %s\n', cfg.contractFixedMode);
    fprintf('contractFixed_kW backup   : %s\n', fmt_real(cfg.contractFixed_kW, 3));
    fprintf('contractFixed y01/yEnd    : %s / %s kW\n', fmt_real(fixedVecDiag(1), 3), fmt_real(fixedVecDiag(end), 3));
    fprintf('contractMin_kW            : %s\n', fmt_real(cfg.contractMin_kW, 3));
    fprintf('contractMax_kW            : %s\n', fmt_real(cfg.contractMax_kW, 3));
    fprintf('facilityMargin            : %s\n', fmt_real(cfg.facilityMargin, 3));
    fprintf('initialFacilityCapacity_kW: %s\n', fmt_real(cfg.initialFacilityCapacity_kW, 3));
    fprintf('facilityInstalledMax_kW   : %s\n', fmt_real(cfg.facilityInstalledMax_kW, 3));
    fprintf('E_max_kWh                 : %s\n', fmt_real(cfg.E_max_kWh, 3));
    fprintf('P_max_kW                  : %s\n', fmt_real(cfg.P_max_kW, 3));
    fprintf('loadGrowthRate            : %s\n', fmt_real(cfg.loadGrowthRate, 6));
    fprintf('projectYears              : %d\n', cfg.projectYears);

catch ME
    fprintf('[ERROR] IIS 계산 실패: %s\n', ME.message);
end

end

%% ============================================================
%  Save outputs
% =============================================================
function savedFiles = save_outputs_revised(out, cfg)
% save_outputs_revised
% ------------------------------------------------------------
% 주요 결과를 MATLAB 내부 구조체와 외부 파일로 저장한다.
% ------------------------------------------------------------

savedFiles = struct();

if ~cfg.saveResults
    return;
end

if ~exist(cfg.outputDir, 'dir')
    mkdir(cfg.outputDir);
end

dispatchFile = fullfile(cfg.outputDir, 'dispatch_table.csv');
annualFile = fullfile(cfg.outputDir, 'annual_summary_table.csv');
costFile = fullfile(cfg.outputDir, 'cost_breakdown_table.csv');
indicatorFile = fullfile(cfg.outputDir, 'required_indicator_table.csv');
modelSummaryFile = fullfile(cfg.outputDir, 'model_summary_table.csv');
matFile = fullfile(cfg.outputDir, 'ess_optimization_result.mat');

writetable(out.sol.dispatchTable, dispatchFile);
writetable(out.sol.annualTable, annualFile);
writetable(out.cost.table, costFile);

indicatorTable = build_indicator_table(out.sol, out.cost, out.noess, cfg);
writetable(indicatorTable, indicatorFile);

modelSummaryTable = build_model_summary_table_revised(out, cfg);
writetable(modelSummaryTable, modelSummaryFile);

outSaved = out; %#ok<NASGU>
save(matFile, 'outSaved');

savedFiles.dispatchTable = dispatchFile;
savedFiles.annualTable = annualFile;
savedFiles.costTable = costFile;
savedFiles.indicatorTable = indicatorFile;
savedFiles.modelSummaryTable = modelSummaryFile;
savedFiles.matFile = matFile;

fprintf('\n================ Saved Output Files ================\n');
fprintf('Dispatch table  : %s\n', dispatchFile);
fprintf('Annual summary  : %s\n', annualFile);
fprintf('Cost breakdown  : %s\n', costFile);
fprintf('Indicator table : %s\n', indicatorFile);
fprintf('Model summary   : %s\n', modelSummaryFile);
fprintf('MAT result      : %s\n', matFile);

end

function modelSummaryTable = build_model_summary_table_revised(out, cfg)
% build_model_summary_table_revised
% ------------------------------------------------------------
% 논문/검산용으로 모델의 최적화 해석과 주요 설정을 저장한다.
% ------------------------------------------------------------

item = strings(0,1);
value = strings(0,1);

    function addItem(k, v)
        item(end+1,1) = string(k); %#ok<AGROW>
        value(end+1,1) = string(v); %#ok<AGROW>
    end

addItem('optimization_type', 'multiyear_integrated_simultaneous_MILP');
addItem('optimization_definition', '20년 전체를 하나의 MILP로 통합하여 풀며, ESS 용량, PCS 출력, 계약전력, 연도별 증설, 열화기반 교체, 시간별 운전을 동시에 결정');
addItem('scenario_id', cfg.scenarioId);
addItem('scenario_name', cfg.scenarioName);
addItem('use_ESS', cfg.useESS);
addItem('optimize_contract', cfg.optimizeContract);
addItem('contract_mode', cfg.contractMode);
addItem('project_years', cfg.projectYears);
addItem('load_growth_rate', cfg.loadGrowthRate);
addItem('replacement_model', 'SOH_80_percent_whole_ESS_binary_replacement_at_year_end');
addItem('replacement_trigger_loss_fraction', cfg.replacementTriggerLossFraction);
addItem('replacement_cost_basis', 'replacementESS_KRW_per_kWh * E_replacement_kWh, where E_replacement_kWh = E_ESS_kWh when z_replace_ESS=1');
addItem('annual_expansion_variable', 'E_ESS_increment_kWh and P_PCS_increment_kW');
if isfield(out, 'meta')
    addItem('n_variables', out.meta.nvar);
    addItem('n_constraints', out.meta.ncon);
end
if isfield(out, 'status')
    addItem('status', out.status);
end

modelSummaryTable = table(item, value);

end

function indicatorTable = build_indicator_table(sol, cost, noess, cfg)
% build_indicator_table
% ------------------------------------------------------------
% 사용자가 제시한 이미지의 주요 지표를 long-format table로 저장한다.
% ------------------------------------------------------------

Y = cfg.projectYears;
metric = strings(0,1);
symbol = strings(0,1);
unit = strings(0,1);
year = zeros(0,1);
value = zeros(0,1);

    function addMetric(metricText, symbolText, unitText, yearVal, valueVal)
        metric(end+1,1) = string(metricText); %#ok<AGROW>
        symbol(end+1,1) = string(symbolText); %#ok<AGROW>
        unit(end+1,1) = string(unitText); %#ok<AGROW>
        year(end+1,1) = yearVal; %#ok<AGROW>
        value(end+1,1) = valueVal; %#ok<AGROW>
    end

for y = 1:Y
    addMetric('ESS 용량', 'E_ESS', 'kWh', y, sol.E_ESS_kWh(y));
    addMetric('열화반영 사용가능 ESS 용량', 'E_usable', 'kWh', y, sol.E_usable_kWh(y));
    addMetric('PCS 출력', 'P_PCS', 'kW', y, sol.P_PCS_kW(y));
    addMetric('계약전력', 'P_contract', 'kW', y, sol.P_contract_kW(y));
    addMetric('계통구매전력 최대값', 'P_grid_max', 'kW', y, sol.annualTable.P_grid_max_kW(y));
    addMetric('피크 저감량', 'Peak_reduction', 'kW', y, sol.annualTable.peak_reduction_kW(y));
    addMetric('충전량', 'E_charge', 'kWh/year', y, sol.annualTable.charge_energy_kWh(y));
    addMetric('방전량', 'E_discharge', 'kWh/year', y, sol.annualTable.discharge_energy_kWh(y));
    addMetric('등가 사이클', 'EFC', 'cycle/year', y, sol.annualTable.equivalent_cycles(y));
    addMetric('배터리 내부 방전량', 'Battery_discharge_energy', 'kWh/year', y, sol.annualTable.battery_discharge_energy_kWh(y));
    addMetric('SOC 최소값', 'SOC_min', 'kWh', y, sol.annualTable.SOC_min_kWh(y));
    addMetric('SOC 최대값', 'SOC_max', 'kWh', y, sol.annualTable.SOC_max_kWh(y));
    addMetric('SOC 최소비율', 'SOC_min_ratio', 'p.u.', y, sol.annualTable.SOC_min_ratio(y));
    addMetric('SOC 최대비율', 'SOC_max_ratio', 'p.u.', y, sol.annualTable.SOC_max_ratio(y));
    addMetric('자연열화 손실량', 'calendar_degradation', 'kWh/year', y, sol.annualTable.calendar_degradation_kWh(y));
    addMetric('사이클 열화 손실량', 'cycle_degradation', 'kWh/year', y, sol.annualTable.cycle_degradation_kWh(y));
    addMetric('교체 전 누적 열화손실량', 'degradation_pre_replace', 'kWh', y, sol.annualTable.degradation_pre_replace_kWh(y));
    addMetric('교체 후 누적 열화손실량', 'degradation_end', 'kWh', y, sol.annualTable.degradation_end_kWh(y));
    addMetric('ESS 전체 교체 여부', 'z_replace_ESS', 'binary', y, sol.annualTable.z_replace_ESS(y));
    addMetric('열화기반 ESS 교체량', 'E_replacement', 'kWh/year', y, sol.annualTable.E_replacement_kWh(y));
    addMetric('자연열화율', 'calendar_degradation_fraction', 'fraction/year', y, sol.annualTable.calendar_degradation_fraction(y));
    addMetric('사이클 열화율', 'cycle_degradation_fraction', 'fraction/year', y, sol.annualTable.cycle_degradation_fraction(y));
    addMetric('누적 열화율', 'cumulative_degradation_fraction', 'fraction', y, sol.annualTable.cumulative_degradation_fraction(y));
    addMetric('사용가능 용량비율', 'usable_capacity_fraction', 'fraction', y, sol.annualTable.usable_capacity_fraction(y));
    addMetric('필요 수전설비용량', 'facility_required', 'kW', y, sol.facility_required_kW(y));
    addMetric('설치 수전설비용량', 'facility_installed', 'kW', y, sol.facility_installed_kW(y));
    addMetric('수전설비 증설량', 'facility_expansion', 'kW', y, sol.facility_expansion_kW(y));
end

operationSavingPV = (noess.energyCostPV + noess.basicCostPV + noess.exceedCostPV) - cost.operationCostPV;
netSavingPV = noess.totalPresentValue - cost.totalPresentValue;

addMetric('전력량요금', 'Energy_cost_PV', 'KRW', 0, cost.energyCostPV);
addMetric('기본요금', 'Basic_cost_PV', 'KRW', 0, cost.basicCostPV);
addMetric('총비용', 'Total_cost_PV', 'KRW', 0, cost.totalPresentValue);
addMetric('설비비 제외 절감액', 'Saving_without_design_cost_PV', 'KRW', 0, operationSavingPV);
addMetric('설비비 포함 순절감액', 'Net_saving_with_design_cost_PV', 'KRW', 0, netSavingPV);
addMetric('수전설비 증설비용', 'Facility_expansion_cost_PV', 'KRW', 0, cost.facilityExpansionCostPV);
addMetric('유지보수비', 'OM_cost_PV', 'KRW', 0, cost.omCostPV);
addMetric('교체비', 'Replacement_cost_PV', 'KRW', 0, cost.replacementCostPV);

indicatorTable = table(metric, symbol, unit, year, value);

end

%% ============================================================
%  Output formatting helpers
% =============================================================
function s = fmt_real(x, decimals)
% fmt_real
% ------------------------------------------------------------
% 숫자를 지수표기 없이 고정 소수점 문자열로 변환한다.
% ------------------------------------------------------------
if nargin < 2
    decimals = 2;
end

if isnan(x)
    s = 'NaN';
    return;
end
if isinf(x)
    if x > 0
        s = 'Inf';
    else
        s = '-Inf';
    end
    return;
end

if abs(x) < 0.5 * 10^(-decimals)
    x = 0;
end
fmt = ['%0.', num2str(decimals), 'f'];
s = sprintf(fmt, x);
end

function s = fmt_unit(x, decimals, unitText)
% fmt_unit
% ------------------------------------------------------------
% 일반 수치에 단위를 붙여 출력한다.
% ------------------------------------------------------------
s = [fmt_real(x, decimals), '[', unitText, ']'];
end

function s = fmt_krw(x)
% fmt_krw
% ------------------------------------------------------------
% 비용을 X[원] 형태로 출력한다.
% ------------------------------------------------------------
if isnan(x)
    s = 'NaN[원]';
    return;
end
if isinf(x)
    if x > 0
        s = 'Inf[원]';
    else
        s = '-Inf[원]';
    end
    return;
end
xRounded = round(x);
numStr = sprintf('%.0f', xRounded);
numStr = add_commas_to_integer_string(numStr);
s = [numStr, '[원]'];
end

function s = add_commas_to_integer_string(numStr)
% add_commas_to_integer_string
% ------------------------------------------------------------
% 정수 문자열에 천 단위 쉼표를 추가한다.
% ------------------------------------------------------------
if isempty(numStr)
    s = numStr;
    return;
end
signText = '';
if numStr(1) == '-'
    signText = '-';
    numStr = numStr(2:end);
end
n = length(numStr);
if n <= 3
    s = [signText, numStr];
    return;
end
firstGroupLen = mod(n, 3);
if firstGroupLen == 0
    firstGroupLen = 3;
end
sBody = numStr(1:firstGroupLen);
pos = firstGroupLen + 1;
while pos <= n
    sBody = [sBody, ',', numStr(pos:pos+2)]; %#ok<AGROW>
    pos = pos + 3;
end
s = [signText, sBody];
end

function print_cost_line(labelText, valueKRW)
% print_cost_line
% ------------------------------------------------------------
% 비용 항목을 X[원] 형식으로 출력한다.
% ------------------------------------------------------------
fprintf('%-38s : %s\n', labelText, fmt_krw(valueKRW));
end

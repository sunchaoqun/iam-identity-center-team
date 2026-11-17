# TEAM — EventBridge 近实时会话审计（替代 CloudTrail Lake）

CloudTrail Lake 自 2026-05-31 起不再接受新客户。本分支为 TEAM 新增 `CLOUDTRAIL_AUDIT_LOGS=eventbridge` 模式，
把 Session activity 的数据源从 CloudTrail Lake 换成 **CloudTrail → EventBridge → DynamoDB** 的推送式管道，前端无需改动。

## 快速部署（约 40 分钟，大部分是 Amplify 构建等待）

```bash
git clone <your-fork> && cd iam-identity-center-team/deployment
cp parameters-template.sh parameters.sh     # 按注释填写
aws sso login --sso-session <your-session>

./init.sh              # 1. 委派管理员（Account / CloudTrail / IAM Identity Center）
./deploy.sh            # 2. 预检 + TEAM 主栈 + Amplify 构建（~20 分钟）
./deploy-forwarder.sh  # 3. 组织 Trail（无则自动创建）+ 等待中心总线 + StackSets 下发转发规则
./integration.sh       # 4. 输出 SAML 参数 → 在 Identity Center 建 TEAM IDC APP
./cognito.sh           # 5. 填好 details.json 后执行
```

## 前置条件
- AWS Organizations（全部功能）+ IAM Identity Center **组织实例**
- 专用 TEAM 成员账号（不要用管理账号）
- `TEAM_ACCOUNT` 中的 Secrets Manager 密钥，键名必须为 `url` 与 `AccessToken`（GitHub classic token：`repo` + `admin:repo_hook`）
- Identity Center 中的组：`team_admin`、`team_auditor`、申请组、审批组；用于 TEAM 的权限集**不得**分配到管理账号

## 新增 / 修改的文件
| 文件 | 作用 |
|---|---|
| `deployment/preflight.sh` | 部署前检查（参数、profile、Region、密钥键名、审计模式） |
| `deployment/deploy-forwarder.sh` | 组织 Trail、等待总线、StackSets 下发 |
| `deployment/session-forwarder.yml` | 成员账号 default bus → TEAM 中心总线 |
| `amplify/backend/custom/cloudtrailLake/*template.json` | `eventbridge` 模式下创建 DynamoDB、中心总线、写入 Lambda |
| `amplify/backend/function/teamgetLogs`、`teamqueryLogs` | `ddb:` queryId 时改查 DynamoDB |

## 验证
```bash
aws dynamodb scan --table-name team-session-events-main --region $REGION --profile $TEAM_ACCOUNT_PROFILE \
  --query "Items[].[eventTime.S, ingestTime.S, eventName.S, pk.S]" --output table
```
`ingestTime - eventTime` 即实际延迟。

## 已知限制
- CloudTrail → EventBridge 为尽力投递（best effort），无官方延迟 SLA
- 只记录 Trail 生效之后的事件；Management 账号不会被 StackSet 覆盖（TEAM 本身也不对其授权）
- 测试时注意控制台 Region 需在 `FORWARDER_REGIONS` 内

## 代表節點可接收傷害的組合式能力，並把有效傷害轉交給 HealthComponent。
## 戰鬥流程只需要尋找這個元件，不要求所有可受傷實體繼承共同基底類別。
extends Node
class_name DamageReceiver

## 實際保存血量的同實體元件。
@export var health_component: HealthComponent
## 關閉時暫時拒絕所有傷害，供訓練靶歸零等待重設使用。
@export var enabled := true


## 接收正數傷害並回報是否成功交付至血量元件。
func receive_damage(amount: float) -> bool:
	if not enabled or health_component == null or amount <= 0.0:
		return false
	return health_component.apply_damage(amount)

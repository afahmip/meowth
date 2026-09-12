package model

type PaymentMethod struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	Emoji     string `json:"emoji"`
	Type      string `json:"type"`
	CreatedAt string `json:"created_at"`
}

package model

type Category struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	Emoji     string `json:"emoji"`
	CreatedAt string `json:"created_at"`
}

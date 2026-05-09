package coze

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseSSEAndAccumulateAnswerText(t *testing.T) {
	input := strings.NewReader(`event: conversation.message.delta
data: {"type":"answer","content_type":"text","content":"你"}

event: ping
data: {"type":"ping"}

event: conversation.message.delta
data: {"message":{"type":"answer","content_type":"text","content":"好"}}

data: [DONE]

`)

	events, err := ParseSSE(input)
	require.NoError(t, err)
	require.Len(t, events, 4)
	require.Equal(t, "你好", AccumulateAnswerText(events))
}

func TestExtractAnswerDeltaIgnoresNonAnswer(t *testing.T) {
	events, err := ParseSSE(strings.NewReader(`event: conversation.message.delta
data: {"type":"verbose","content_type":"text","content":"ignore"}

event: conversation.message.delta
data: {"type":"answer","content_type":"card","content":"ignore"}

event: conversation.message.delta
data: {"type":"answer","content_type":"text","content":"keep"}

`))
	require.NoError(t, err)
	require.Equal(t, "keep", AccumulateAnswerText(events))
}

func TestParseSSESupportsMultilineData(t *testing.T) {
	events, err := ParseSSE(strings.NewReader("event: conversation.message.delta\n" +
		"data: {\"type\":\"answer\",\n" +
		"data: \"content_type\":\"text\",\n" +
		"data: \"content\":\"ok\"}\n\n"))
	require.NoError(t, err)
	require.Equal(t, "ok", AccumulateAnswerText(events))
}

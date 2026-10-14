@testable import Emma
import XCTest

final class ChatStreamTests: XCTestCase {
    private func run(_ chunks: [String]) throws -> (ChatStream, String) {
        var stream = ChatStream()
        var text = ""
        for chunk in chunks {
            text += stream.apply(try JSON.parse(Data(chunk.utf8))) ?? ""
        }
        return (stream, text)
    }

    func testAssemblesText() throws {
        let (stream, text) = try run([
            #"{"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#,
            #"{"choices":[{"index":0,"delta":{"content":"Paris"}}]}"#,
            #"{"choices":[{"index":0,"delta":{"content":" is the capital."}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        ])
        XCTAssertEqual(text, "Paris is the capital.")
        XCTAssertEqual(stream.finishReason, "stop")
        XCTAssertTrue(stream.toolCalls.isEmpty)
        XCTAssertEqual(stream.message, .object(["role": "assistant", "content": "Paris is the capital."]))
    }

    func testReassemblesToolCallArguments() throws {
        let (stream, text) = try run([
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calendar","arguments":""}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"day\":"}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"today\"}"}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])
        XCTAssertEqual(text, "")
        XCTAssertEqual(stream.finishReason, "tool_calls")
        XCTAssertEqual(stream.toolCalls, [ChatStream.ToolCall(id: "call_1", name: "calendar", arguments: #"{"day":"today"}"#)])
        XCTAssertEqual(stream.message["tool_calls"], .array([.object([
            "id": "call_1", "type": "function",
            "function": .object(["name": "calendar", "arguments": .string(#"{"day":"today"}"#)]),
        ])]))
    }

    func testIgnoresChunksWithoutChoices() throws {
        let (stream, text) = try run([#"{"choices":[]}"#, #"{"object":"chat.completion.chunk"}"#])
        XCTAssertEqual(text, "")
        XCTAssertNil(stream.finishReason)
    }
}

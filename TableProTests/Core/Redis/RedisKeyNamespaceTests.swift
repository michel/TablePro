import Testing
@testable import TablePro

@Suite("Redis Key Namespace")
struct RedisKeyNamespaceTests {

    // MARK: - buildTree Grouping

    @Test("Simple grouping by colon separator")
    func simpleGrouping() {
        let keys = ["user:1", "user:2", "session:abc"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 2)
        let names = tree.map(\.name)
        #expect(names.contains("user"))
        #expect(names.contains("session"))
    }

    @Test("Keys without separator produce a single no-namespace node")
    func noSeparatorKeys() {
        let keys = ["foo", "bar", "baz"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "(no namespace)")
        #expect(tree[0].id == "")
        #expect(tree[0].keyCount == 3)
    }

    @Test("Mixed namespaced and orphaned keys")
    func mixedKeys() {
        let keys = ["user:1", "user:2", "orphan"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 2)
        #expect(tree[0].name == "user")
        #expect(tree[1].name == "(no namespace)")
    }

    @Test("Empty key list returns empty array")
    func emptyKeys() {
        let tree = RedisKeyNamespace.buildTree(from: [])
        #expect(tree.isEmpty)
    }

    @Test("Single key with separator creates one namespace")
    func singleKeyWithSeparator() {
        let tree = RedisKeyNamespace.buildTree(from: ["cache:item"])

        #expect(tree.count == 1)
        #expect(tree[0].name == "cache")
        #expect(tree[0].keyCount == 1)
    }

    @Test("Single key without separator creates no-namespace node")
    func singleKeyWithoutSeparator() {
        let tree = RedisKeyNamespace.buildTree(from: ["standalone"])

        #expect(tree.count == 1)
        #expect(tree[0].name == "(no namespace)")
        #expect(tree[0].keyCount == 1)
    }

    // MARK: - Deep Nesting

    @Test("Deep nesting produces recursive children")
    func deepNesting() {
        let keys = ["a:b:c:1", "a:b:c:2", "a:b:d:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        let aNode = tree[0]
        #expect(aNode.name == "a")
        #expect(aNode.id == "a:")
        #expect(aNode.keyCount == 3)

        #expect(aNode.children.count == 1)
        let bNode = aNode.children[0]
        #expect(bNode.name == "b")
        #expect(bNode.id == "a:b:")
        #expect(bNode.keyCount == 3)

        #expect(bNode.children.count == 2)
        let childNames = bNode.children.map(\.name)
        #expect(childNames == ["c", "d"])

        let cNode = bNode.children.first { $0.name == "c" }!
        #expect(cNode.keyCount == 2)
        #expect(cNode.id == "a:b:c:")
        #expect(cNode.isLeaf)

        let dNode = bNode.children.first { $0.name == "d" }!
        #expect(dNode.keyCount == 1)
        #expect(dNode.id == "a:b:d:")
        #expect(dNode.isLeaf)
    }

    // MARK: - Custom Separator

    @Test("Custom dot separator groups correctly")
    func customDotSeparator() {
        let keys = ["app.config.db", "app.config.cache", "app.log"]
        let tree = RedisKeyNamespace.buildTree(from: keys, separator: ".")

        #expect(tree.count == 1)
        let appNode = tree[0]
        #expect(appNode.name == "app")
        #expect(appNode.id == "app.")
        #expect(appNode.keyCount == 3)

        #expect(appNode.children.count == 1)
        let configNode = appNode.children.first { $0.name == "config" }
        #expect(configNode != nil)
        #expect(configNode?.keyCount == 2)
        #expect(configNode?.id == "app.config.")
    }

    @Test("Custom slash separator")
    func customSlashSeparator() {
        let keys = ["api/v1/users", "api/v1/posts", "api/v2/users"]
        let tree = RedisKeyNamespace.buildTree(from: keys, separator: "/")

        #expect(tree.count == 1)
        #expect(tree[0].name == "api")
        #expect(tree[0].id == "api/")
    }

    @Test("Multi-character separator")
    func multiCharSeparator() {
        let keys = ["ns::key1", "ns::key2", "other::key3"]
        let tree = RedisKeyNamespace.buildTree(from: keys, separator: "::")

        #expect(tree.count == 2)
        let names = tree.map(\.name)
        #expect(names.contains("ns"))
        #expect(names.contains("other"))
        #expect(tree.first { $0.name == "ns" }?.id == "ns::")
    }

    // MARK: - scanPattern

    @Test("scanPattern appends asterisk to id")
    func scanPattern() {
        let ns = RedisKeyNamespace(id: "user:", name: "user", keyCount: 5, children: [])
        #expect(ns.scanPattern == "user:*")
    }

    @Test("scanPattern for nested namespace")
    func scanPatternNested() {
        let ns = RedisKeyNamespace(id: "app:config:", name: "config", keyCount: 2, children: [])
        #expect(ns.scanPattern == "app:config:*")
    }

    @Test("scanPattern for no-namespace node with empty id")
    func scanPatternNoNamespace() {
        let ns = RedisKeyNamespace(id: "", name: "(no namespace)", keyCount: 3, children: [])
        #expect(ns.scanPattern == "*")
    }

    // MARK: - isLeaf

    @Test("isLeaf is true when children are empty")
    func isLeafTrue() {
        let ns = RedisKeyNamespace(id: "leaf:", name: "leaf", keyCount: 1, children: [])
        #expect(ns.isLeaf)
    }

    @Test("isLeaf is false when children exist")
    func isLeafFalse() {
        let child = RedisKeyNamespace(id: "parent:child:", name: "child", keyCount: 1, children: [])
        let ns = RedisKeyNamespace(id: "parent:", name: "parent", keyCount: 2, children: [child])
        #expect(!ns.isLeaf)
    }

    @Test("Leaf nodes from buildTree have no children")
    func leafNodesFromBuildTree() {
        let keys = ["x:1", "x:2"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].isLeaf)
    }

    // MARK: - keyCount Accuracy

    @Test("keyCount reflects the number of keys in each namespace")
    func keyCountAccuracy() {
        let keys = ["user:1", "user:2", "user:3", "session:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        let userNs = tree.first { $0.name == "user" }
        #expect(userNs != nil)
        #expect(userNs?.keyCount == 3)

        let sessionNs = tree.first { $0.name == "session" }
        #expect(sessionNs != nil)
        #expect(sessionNs?.keyCount == 1)
    }

    @Test("keyCount for no-namespace matches ungrouped key count")
    func keyCountUngrouped() {
        let keys = ["a", "b", "c", "ns:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        let ungrouped = tree.first { $0.name == "(no namespace)" }
        #expect(ungrouped?.keyCount == 3)
    }

    @Test("Parent keyCount includes all descendant keys")
    func parentKeyCountIncludesDescendants() {
        let keys = ["a:b:1", "a:b:2", "a:c:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].keyCount == 3)
        let bChild = tree[0].children.first { $0.name == "b" }
        #expect(bChild?.keyCount == 2)
        let cChild = tree[0].children.first { $0.name == "c" }
        #expect(cChild?.keyCount == 1)
    }

    // MARK: - id Construction

    @Test("id includes trailing separator")
    func idIncludesTrailingSeparator() {
        let keys = ["cache:item1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].id == "cache:")
    }

    @Test("Nested id includes full prefix chain")
    func nestedIdFullPrefix() {
        let keys = ["a:b:c:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].id == "a:")
        #expect(tree[0].children[0].id == "a:b:")
        #expect(tree[0].children[0].children[0].id == "a:b:c:")
    }

    @Test("No-namespace node has empty id")
    func noNamespaceEmptyId() {
        let keys = ["standalone"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].id == "")
    }

    // MARK: - name Value

    @Test("name is the prefix without separator")
    func nameWithoutSeparator() {
        let keys = ["metrics:cpu", "metrics:memory"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].name == "metrics")
    }

    @Test("Nested child name is just the local segment")
    func nestedChildName() {
        let keys = ["a:b:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].children[0].name == "b")
    }

    // MARK: - Alphabetical Ordering

    @Test("Namespaces are sorted alphabetically")
    func alphabeticalOrdering() {
        let keys = ["zebra:1", "alpha:1", "middle:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        let names = tree.map(\.name)
        #expect(names == ["alpha", "middle", "zebra"])
    }

    @Test("Children within a namespace are sorted alphabetically")
    func childrenAlphabeticalOrdering() {
        let keys = ["ns:z:1", "ns:a:1", "ns:m:1"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        let childNames = tree[0].children.map(\.name)
        #expect(childNames == ["a", "m", "z"])
    }

    // MARK: - Ungrouped Keys at End

    @Test("Ungrouped keys appear after namespaced groups")
    func ungroupedAtEnd() {
        let keys = ["user:1", "orphan", "session:2"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 3)
        #expect(tree.last?.name == "(no namespace)")
        #expect(tree[0].name == "session")
        #expect(tree[1].name == "user")
    }

    @Test("Multiple ungrouped keys consolidated into single node at end")
    func multipleUngroupedConsolidated() {
        let keys = ["ns:1", "orphan1", "orphan2", "orphan3"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 2)
        #expect(tree.last?.name == "(no namespace)")
        #expect(tree.last?.keyCount == 3)
    }

    // MARK: - Edge Cases

    @Test("Key that is just the separator produces empty prefix namespace")
    func keyIsSeparator() {
        let keys = [":value"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "")
        #expect(tree[0].id == ":")
    }

    @Test("Key with trailing separator")
    func keyWithTrailingSeparator() {
        let keys = ["prefix:"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "prefix")
        #expect(tree[0].keyCount == 1)
    }

    @Test("Key with consecutive separators")
    func consecutiveSeparators() {
        let keys = ["a::b"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "a")
        #expect(tree[0].id == "a:")
    }

    @Test("All keys in the same namespace")
    func allSameNamespace() {
        let keys = ["ns:a", "ns:b", "ns:c", "ns:d", "ns:e"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "ns")
        #expect(tree[0].keyCount == 5)
    }

    @Test("Large number of distinct namespaces are sorted")
    func manyNamespacesSorted() {
        let prefixes = ["zulu", "alpha", "bravo", "delta", "charlie", "echo"]
        let keys = prefixes.map { "\($0):1" }
        let tree = RedisKeyNamespace.buildTree(from: keys)

        let names = tree.map(\.name)
        #expect(names == prefixes.sorted())
    }

    @Test("Duplicate keys are counted individually")
    func duplicateKeys() {
        let keys = ["ns:key", "ns:key", "ns:key"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree[0].keyCount == 3)
    }

    @Test("Only ungrouped keys produces single no-namespace node")
    func onlyUngroupedKeys() {
        let keys = ["alpha", "beta", "gamma"]
        let tree = RedisKeyNamespace.buildTree(from: keys)

        #expect(tree.count == 1)
        #expect(tree[0].name == "(no namespace)")
        #expect(tree[0].keyCount == 3)
        #expect(tree[0].isLeaf)
    }

    // MARK: - Identifiable and Hashable

    @Test("Identifiable id matches the id property")
    func identifiableConformance() {
        let ns = RedisKeyNamespace(id: "test:", name: "test", keyCount: 1, children: [])
        #expect(ns.id == "test:")
    }

    @Test("Equal namespaces are hashable to the same value")
    func hashableConformance() {
        let ns1 = RedisKeyNamespace(id: "x:", name: "x", keyCount: 1, children: [])
        let ns2 = RedisKeyNamespace(id: "x:", name: "x", keyCount: 1, children: [])
        #expect(ns1 == ns2)

        var set = Set<RedisKeyNamespace>()
        set.insert(ns1)
        set.insert(ns2)
        #expect(set.count == 1)
    }

    @Test("Different namespaces are not equal")
    func hashableDifferentNamespaces() {
        let ns1 = RedisKeyNamespace(id: "a:", name: "a", keyCount: 1, children: [])
        let ns2 = RedisKeyNamespace(id: "b:", name: "b", keyCount: 1, children: [])
        #expect(ns1 != ns2)
    }

    // MARK: - buildTree with Custom Separator Edge Cases

    @Test("Custom separator not present in any key gives one no-namespace node")
    func customSeparatorNotPresent() {
        let keys = ["user:1", "user:2"]
        let tree = RedisKeyNamespace.buildTree(from: keys, separator: ".")

        #expect(tree.count == 1)
        #expect(tree[0].name == "(no namespace)")
        #expect(tree[0].keyCount == 2)
    }

    @Test("Empty separator treats every key as having an empty prefix")
    func emptySeparator() {
        let keys = ["abc", "def"]
        let tree = RedisKeyNamespace.buildTree(from: keys, separator: "")

        #expect(!tree.isEmpty)
    }
}

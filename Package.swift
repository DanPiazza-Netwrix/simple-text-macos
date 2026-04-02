// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleText",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/Neon",           branch: "main"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", branch: "main"),
        // External grammars (packages with properly hardcoded scanner.c sources)
        .package(url: "https://github.com/tree-sitter/tree-sitter-json",       from: "0.21.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift",      branch: "with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go",         from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust",       from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash",       from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html",       from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java",       from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby",       from: "0.21.0"),
        // Python, JavaScript, CSS, YAML are vendored locally (their Package.swift
        // uses a dynamic FileManager.fileExists check for scanner.c that fails in
        // SPM manifest evaluation, so we compile the C sources directly).
    ],
    targets: [
        // ── Vendored grammar targets (C sources only, no external deps) ──────
        .target(
            name: "TreeSitterPython",
            path: "Sources/Grammars/Python",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterJavaScript",
            path: "Sources/Grammars/JavaScript",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterCSS",
            path: "Sources/Grammars/CSS",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterYAML",
            path: "Sources/Grammars/YAML",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterPowershell",
            path: "Sources/Grammars/PowerShell",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        // ── Main app target ──────────────────────────────────────────────────
        .executableTarget(
            name: "SimpleText",
            dependencies: [
                "Neon",
                .product(name: "SwiftTreeSitter",     package: "SwiftTreeSitter"),
                // External grammar products
                .product(name: "TreeSitterJSON",       package: "tree-sitter-json"),
                .product(name: "TreeSitterSwift",      package: "tree-sitter-swift"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterGo",         package: "tree-sitter-go"),
                .product(name: "TreeSitterRust",       package: "tree-sitter-rust"),
                .product(name: "TreeSitterBash",       package: "tree-sitter-bash"),
                .product(name: "TreeSitterHTML",       package: "tree-sitter-html"),
                .product(name: "TreeSitterJava",       package: "tree-sitter-java"),
                .product(name: "TreeSitterRuby",       package: "tree-sitter-ruby"),
                // Vendored grammar targets
                "TreeSitterPython",
                "TreeSitterJavaScript",
                "TreeSitterCSS",
                "TreeSitterYAML",
                "TreeSitterPowershell",
            ],
            path: "Sources/SimpleText",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

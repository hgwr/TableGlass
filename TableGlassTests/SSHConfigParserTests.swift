import TableGlassKit
import Testing

struct SSHConfigParserTests {
    @Test func parsesHostAliasesInOrder() {
        let config = """
        Host bastion
            HostName 10.0.0.5
        Host staging staging-alt
            User deploy
        # Commented host should be ignored
        Host production
        Host staging
        Host *
        """

        let aliases = SSHConfigParser.parseHostAliases(from: config)

        #expect(aliases == ["bastion", "staging", "staging-alt", "production"])
    }

    @Test func ignoresWildcardsAndEmptyLines() {
        let config = """

        # Leading comment
        Host jump ?wildcard !negated
        Host   
        Host    analytics
        Host backup* test
        """

        let aliases = SSHConfigParser.parseHostAliases(from: config)

        #expect(aliases == ["analytics"])
    }
}

# tvly-search

Tells the agent how to read Tavily search results the first time in a session that it runs `tvly search`, beside the first result set: check the top score before trusting any result, and query with one plain phrase.

It extends Tavily's search skill without editing it, so the skill still updates cleanly. It is useful only where the Tavily CLI, `tvly`, is installed.

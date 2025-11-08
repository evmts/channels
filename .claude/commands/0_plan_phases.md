## Goal

Create a phased approach to building a state channel implementation.

## Useful context

The following context should be looked at before plan anything

@docs/prd.md - The current product requirement doc. This is a living doc that we can update as plan changes
@docs/context.md - Chat GPT deep research about channels that has useful research and concerns that can be further researched when relavent.
@docs/go-nitro-api.md - A breakdown of the go-nitro api that can be used as reference api to inspire ours

Also go-nitro source code
@go-nitro/architecture.md - architecture doc
@go-nitro/abi/
@go-nitro/channel/
@go-nitro/cmd/
@go-nitro/crypto/
@go-nitro/docker/
@go-nitro/docs/research-papers.md
@go-nitro/docs/faqs.md
@go-nitro/docs/index.md
@go-nitro/docs/applications/_.md
@go-nitro/docs/protocol-tutorial/_.md
@go-nitro/docs/user-flows/0010-user-flows.md
@go-nitro/internal/

# `go-nitro` Node

Our [integration tests](./node_test/readme.md) give the best idea of how to use the API. Another useful resource is [the godoc](https://pkg.go.dev/github.com/statechannels/go-nitro/node#Node) description of the `go-nitro.Node` API.

Broadly, consumers will construct a go-nitro `Node`, possibly using injected dependencies. Then, they can create channels and send payments:

```Go
 import nc "github.com/statechannels/go-nitro/node"

 nitroNode := nc.New(
                    messageservice,
                    chain,
                    storeA,
                    logDestination,
                    nil,
                    nil
                )
response := nitroNode.CreateLedgerChannel(hub.Address, 0, someOutcome)
nitroNode.WaitForCompletedObjective(response.objectiveId)

response = nitroNode.CreateVirtualPaymentChannel([hub.Address],bob.Address, defaultChallengeDuration, someOtherOutcome)
nitroNode.WaitForCompletedObjective(response.objectiveId)

for i := 0; i < len(10); i++ {
    nitroNode.Pay(response.ChannelId, big.NewInt(int64(5)))
}

response = nitroNode.CloseVirtualChannel(response.ChannelId)
nitroNode.WaitForCompletedObjective(response.objectiveId)
```

@go-nitro/node/

# Nitro typescript packages

This directory contains work related to a UI for a go-nitro node.

UI component demos deployed here: https://nitro-storybook.netlify.app/

Latest GUI from `main` branch deployed here https://nitro-gui.netlify.app/

@go-nitro/packages/nitro-gui
@go-nitro/packages/nitro-protocol
@go-nitro/packages/nitro-rpc-client
@go-nitro/packages/payment-proxy-client

// Package main is the entry point for the Fastly Terraform provider.
package main

import (
	"context"
	"flag"
	"log"

	"github.com/hashicorp/terraform-plugin-sdk/v2/plugin"

	"github.com/fastly/terraform-provider-fastly/fastly"
)

const noLogPrefix = 0

func main() {
	var debugMode bool

	flag.BoolVar(&debugMode, "debug", false, "set to true to run the provider with support for debuggers like delve")
	flag.Parse()

	opts := &plugin.ServeOpts{ProviderFunc: fastly.Provider}

	// Prevent logger from prepending date/time to logs, which breaks log-level parsing/filtering
	log.SetFlags(noLogPrefix)

	if debugMode {
		err := plugin.Debug(context.Background(), "fastly/fastly", opts)
		if err != nil {
			log.Fatal(err.Error())
		}
		return
	}

	plugin.Serve(opts)
}

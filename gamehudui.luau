return create("ScreenGui")({
	Name = "In-Game HUD",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

	create("ImageButton")({
		Name = "Squad Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.118646, 0.011111),
		Size = UDim2.fromScale(0.103281, 0.059444),

		create("ImageLabel")({
			Name = "Art",
			BackgroundTransparency = 1,
			Image = "rbxassetid://102488643301775",
			Interactable = false,
			Position = UDim2.fromScale(-0.124054, -0.274143),
			Size = UDim2.fromScale(1.24861, 1.76947),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 3.08878,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Wave Info Container",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.499974, 0.011111),
		Size = UDim2.fromScale(0.243906, 0.170556),
		ZIndex = 2,

		create("Frame")({
			Name = "Wave Container",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.085415, 0),
			Size = UDim2.fromScale(0.829169, 0.522258),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://119386316212396",
				Interactable = false,
				Position = UDim2.fromScale(-0.063353, -0.182952),
				Size = UDim2.fromScale(1.12696, 1.51351),
			}),

			create("TextLabel")({
				Name = "Wave Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.21298, 0.171518),
				Size = UDim2.fromScale(0.620242, 0.654886),
				Text = "WAVE 2",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({}),
			}),
		}),

		create("Frame")({
			Name = "Boss Container",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.542888),
			Size = UDim2.fromScale(1, 0.457112),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://105424574669114",
				Interactable = false,
				Position = UDim2.fromScale(-0.05253, -0.209026),
				Size = UDim2.fromScale(1.10527, 1.5867),
			}),

			create("Frame")({
				Name = "Boss Tag UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.18407, 0.190024),
				Size = UDim2.fromScale(0.215674, 0.285036),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://105276233832108",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Tag Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.138614, 0.229167),
					Size = UDim2.fromScale(0.780594, 0.541667),
					Text = "NEXT BOSS",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 22,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Boss Name",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.414691, 0.172209),
				Size = UDim2.fromScale(0.42665, 0.320665),
				Text = "THE COVE KING",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 44,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 2.54235,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Next Wave Announcement",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.499974, 0.211111),
		Size = UDim2.fromScale(0.191823, 0.159259),
		ZIndex = 3,

		create("Frame")({
			Name = "Announcement Plate",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0.373256),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://96359751034255",
				Interactable = false,
				Position = UDim2.fromScale(-0.066793, -0.274143),
				Size = UDim2.fromScale(1.13386, 1.76947),
			}),

			create("TextLabel")({
				Name = "Announcement Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.202824, 0.272586),
				Size = UDim2.fromScale(0.642194, 0.451713),
				Text = "NEXT WAVE IN",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),
		}),

		create("Frame")({
			Name = "Countdown UI",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.369807, 0.44186),
			Size = UDim2.fromScale(0.260657, 0.55814),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://94093865067334",
				Interactable = false,
				Position = UDim2.fromScale(-0.325, -0.24375),
				Size = UDim2.fromScale(1.65, 1.65),
			}),

			create("TextLabel")({
				Name = "Button Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.317708, 0.145833),
				Size = UDim2.fromScale(0.39375, 0.708333),
				Text = "3",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 2.14128,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Skip Wave Container",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.925, 0.01),
		Size = UDim2.fromScale(0.211042, 0.128889),
		ZIndex = 4,

		create("ImageButton")({
			Name = "Skip Wave Button",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.766041, 0.591954),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://136264706820933",
				Interactable = false,
				Position = UDim2.fromScale(-0.083763, -0.220874),
				Size = UDim2.fromScale(1.16753, 1.63107),
			}),
		}),

		create("Frame")({
			Name = "Skip Vote UI",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.772952, 0.037356),
			Size = UDim2.fromScale(0.227048, 0.517241),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://87979913592103",
				Interactable = false,
				Size = UDim2.fromScale(1, 1),
			}),

			create("TextLabel")({
				Name = "Badge Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.293478, 0.298611),
				Size = UDim2.fromScale(0.446087, 0.402778),
				Text = "0/1",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),
		}),

		create("Frame")({
			Name = "Auto Skip Container",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.012833, 0.626437),
			Size = UDim2.fromScale(0.937808, 0.373563),
			ZIndex = 4,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://122769094588401",
				Interactable = false,
				Position = UDim2.fromScale(-0.075789, -0.415385),
				Size = UDim2.fromScale(1.15158, 2.10769),
			}),

			create("TextLabel")({
				Name = "Auto Skip Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.052632, 0.307692),
				Size = UDim2.fromScale(0.301263, 0.384615),
				Text = "AUTO-SKIP",
				TextColor3 = Color3.fromRGB(185, 169, 217),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 2.91092,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("ImageButton")({
		Name = "Settings Button",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.979167, 0.014815),
		Size = UDim2.fromScale(0.029167, 0.051852),
		ZIndex = 5,

		create("ImageLabel")({
			Name = "Art",
			BackgroundTransparency = 1,
			Image = "rbxassetid://117907024936005",
			Interactable = false,
			Position = UDim2.fromScale(-0.514286, -0.385714),
			Size = UDim2.fromScale(2.02857, 2.02857),
		}),

		create("UIAspectRatioConstraint")({
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Usable Items Container",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.982708, 0.155556),
		Size = UDim2.fromScale(0.113281, 0.101296),
		ZIndex = 6,

		create("ImageButton")({
			Name = "Heal All Button",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.503448, 1),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://96605410628882",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.149909),
				Size = UDim2.fromScale(1.47032, 1.47166),
			}),
		}),

		create("ImageButton")({
			Name = "Nuke All Button",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.496552, 0),
			Size = UDim2.fromScale(0.503448, 1),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://81873692731083",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.149909),
				Size = UDim2.fromScale(1.47032, 1.47166),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 1.98812,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Upgrades Container",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.017344, 0.444167),
		Size = UDim2.fromScale(0.085156, 0.329074),
		ZIndex = 7,

		create("TextLabel")({
			Name = "Upgrades Title",
			BackgroundTransparency = 1,
			FontFace = Font.new(
				"rbxasset://fonts/families/Montserrat.json",
				Enum.FontWeight.Heavy,
				Enum.FontStyle.Normal
			),
			Position = UDim2.fromScale(0.040979, 0),
			Size = UDim2.fromScale(0.713394, 0.056275),
			Text = "UPGRADES",
			TextColor3 = Color3.fromRGB(185, 169, 217),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 2,

			create("UITextSizeConstraint")({
				MaxTextSize = 32,
			}),
		}),

		create("ImageButton")({
			Name = "Upgrade Card 01",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.080473),
			Size = UDim2.fromScale(1, 0.452448),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://139807635165862",
				Interactable = false,
				Position = UDim2.fromScale(-0.157798, -0.118159),
				Size = UDim2.fromScale(1.31499, 1.33706),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.725994, 0.083333),
				Size = UDim2.fromScale(0.183486, 0.186567),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://106777040389792",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.3, 0.166667),
					Size = UDim2.fromScale(0.432, 0.666667),
					Text = "C",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 32,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Price Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.540423),
				Size = UDim2.fromScale(0.284037, 0.180348),
				Text = "$10",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),

			create("TextLabel")({
				Name = "Card Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.779851),
				Size = UDim2.fromScale(0.45578, 0.124378),
				Text = "HEALTH",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 4,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("ImageButton")({
			Name = "Upgrade Card 02",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.547552),
			Size = UDim2.fromScale(1, 0.452448),
			ZIndex = 4,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://111485632705697",
				Interactable = false,
				Position = UDim2.fromScale(-0.157798, -0.118159),
				Size = UDim2.fromScale(1.31499, 1.33706),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.725994, 0.083333),
				Size = UDim2.fromScale(0.183486, 0.186567),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://106777040389792",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.283333, 0.166667),
					Size = UDim2.fromScale(0.468, 0.666667),
					Text = "V",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 32,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Price Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.540423),
				Size = UDim2.fromScale(0.383119, 0.180348),
				Text = "$150",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),

			create("TextLabel")({
				Name = "Card Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.779851),
				Size = UDim2.fromScale(0.561468, 0.124378),
				Text = "SHOTGUN",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 4,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 0.460045,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Money Products Container",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.018125, 0.799259),
		Size = UDim2.fromScale(0.130417, 0.16963),
		ZIndex = 8,

		create("Frame")({
			Name = "Money Product Button 01",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0.497817),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://133849700511605",
				Interactable = false,
				Position = UDim2.fromScale(-0.103834, -0.14693),
				Size = UDim2.fromScale(1.20767, 1.51754),
			}),

			create("TextLabel")({
				Name = "Product Value",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.260383, 0.350877),
				Size = UDim2.fromScale(0.547764, 0.350877),
				Text = "+$99,999",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 52,
				}),
			}),

			create("Frame")({
				Name = "Price Tag UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.739617, 0),
				Size = UDim2.fromScale(0.255591, 0.263158),
				ZIndex = 3,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://90510248158128",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Tag Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.21875, 0.229167),
					Size = UDim2.fromScale(0.6075, 0.541667),
					Text = "R$ 99",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 22,
					}),
				}),
			}),
		}),

		create("Frame")({
			Name = "Money Product Button 02",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.502183),
			Size = UDim2.fromScale(1, 0.497817),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://96646665217373",
				Interactable = false,
				Position = UDim2.fromScale(-0.103834, -0.14693),
				Size = UDim2.fromScale(1.20767, 1.51754),
			}),

			create("TextLabel")({
				Name = "Product Value",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.260383, 0.350877),
				Size = UDim2.fromScale(0.457188, 0.350877),
				Text = "+$1,000",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 52,
				}),
			}),

			create("Frame")({
				Name = "Price Tag UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.739617, 0),
				Size = UDim2.fromScale(0.223642, 0.263158),
				ZIndex = 3,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://90862369608039",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Tag Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.25, 0.229167),
					Size = UDim2.fromScale(0.54, 0.541667),
					Text = "R$ 9",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 22,
					}),
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 1.36681,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Ult Charge Container",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.897917, 0.757407),
		Size = UDim2.fromScale(0.019792, 0.138889),
		ZIndex = 9,

		create("ImageLabel")({
			Name = "Art",
			BackgroundTransparency = 1,
			Image = "rbxassetid://138507042702294",
			Interactable = false,
			Size = UDim2.fromScale(1, 1),
		}),

		create("Frame")({
			Name = "Ult Charge UI",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0.173333),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://80967780391968",
				Interactable = false,
				Size = UDim2.fromScale(1, 1),
			}),

			create("TextLabel")({
				Name = "Badge Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.263158, 0.173077),
				Size = UDim2.fromScale(0.511579, 0.653846),
				Text = "29",
				TextColor3 = Color3.fromRGB(13, 10, 28),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 28,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 0.253333,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Abilities Container",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.982708, 0.521019),
		Size = UDim2.fromScale(0.085156, 0.482778),
		ZIndex = 10,

		create("TextLabel")({
			Name = "Abilities Title",
			BackgroundTransparency = 1,
			FontFace = Font.new(
				"rbxasset://fonts/families/Montserrat.json",
				Enum.FontWeight.Heavy,
				Enum.FontStyle.Normal
			),
			Position = UDim2.fromScale(0.365138, 0),
			Size = UDim2.fromScale(0.640734, 0.038358),
			Text = "ABILITIES",
			TextColor3 = Color3.fromRGB(185, 169, 217),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 2,

			create("UITextSizeConstraint")({
				MaxTextSize = 32,
			}),
		}),

		create("ImageButton")({
			Name = "Ability Card 01",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.054852),
			Size = UDim2.fromScale(1, 0.3084),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://127534093757665",
				Interactable = false,
				Position = UDim2.fromScale(-0.157798, -0.118159),
				Size = UDim2.fromScale(1.31499, 1.33706),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.725994, 0.083333),
				Size = UDim2.fromScale(0.183486, 0.186567),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://106777040389792",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.283333, 0.166667),
					Size = UDim2.fromScale(0.468, 0.666667),
					Text = "G",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 32,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Price Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.540423),
				Size = UDim2.fromScale(0.317064, 0.180348),
				Text = "$50",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),

			create("TextLabel")({
				Name = "Card Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.779851),
				Size = UDim2.fromScale(0.561468, 0.124378),
				Text = "GRENADE",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 4,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("ImageButton")({
			Name = "Ability Card 02",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.373226),
			Size = UDim2.fromScale(1, 0.3084),
			ZIndex = 4,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://81637994815500",
				Interactable = false,
				Position = UDim2.fromScale(-0.157798, -0.118159),
				Size = UDim2.fromScale(1.31499, 1.33706),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.725994, 0.083333),
				Size = UDim2.fromScale(0.183486, 0.186567),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://106777040389792",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.283333, 0.166667),
					Size = UDim2.fromScale(0.468, 0.666667),
					Text = "X",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 32,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Price Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.540423),
				Size = UDim2.fromScale(0.330275, 0.180348),
				Text = "$40",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),

			create("TextLabel")({
				Name = "Card Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.779851),
				Size = UDim2.fromScale(0.686972, 0.124378),
				Text = "BARRICADE",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 4,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("ImageButton")({
			Name = "Ability Card 03",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.6916),
			Size = UDim2.fromScale(1, 0.3084),
			ZIndex = 5,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://97897316009467",
				Interactable = false,
				Position = UDim2.fromScale(-0.157798, -0.118159),
				Size = UDim2.fromScale(1.31499, 1.33706),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.725994, 0.083333),
				Size = UDim2.fromScale(0.183486, 0.186567),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://106777040389792",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.266667, 0.166667),
					Size = UDim2.fromScale(0.504, 0.666667),
					Text = "Q",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 32,
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Price Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.540423),
				Size = UDim2.fromScale(0.317064, 0.180348),
				Text = "ULT",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 3,

				create("UITextSizeConstraint")({
					MaxTextSize = 48,
				}),
			}),

			create("TextLabel")({
				Name = "Card Label",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.114373, 0.779851),
				Size = UDim2.fromScale(0.607706, 0.124378),
				Text = "AIRSTRIKE",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 4,

				create("UITextSizeConstraint")({
					MaxTextSize = 32,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 0.313579,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Player Container",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.708854, 0.575926),
		Size = UDim2.fromScale(0.125, 0.237037),
		ZIndex = 11,

		create("ImageLabel")({
			Name = "Image",
			BackgroundTransparency = 1,
			Image = "rbxassetid://125256443016297",
			Interactable = false,
			Size = UDim2.fromScale(1, 1),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 0.9375,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Round Money Container",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.874074),
		Size = UDim2.fromScale(0.142708, 0.077778),
		ZIndex = 12,

		create("ImageLabel")({
			Name = "Art",
			BackgroundTransparency = 1,
			Image = "rbxassetid://74780406950195",
			Interactable = false,
			Size = UDim2.fromScale(1, 1),
		}),

		create("Frame")({
			Name = "Money Plate",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.306569, 0),
			Size = UDim2.fromScale(0.693431, 1),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://135702173692848",
				Interactable = false,
				Position = UDim2.fromScale(-0.151579, -0.257143),
				Size = UDim2.fromScale(1.30316, 1.68571),
			}),

			create("TextLabel")({
				Name = "Round Money Value",
				BackgroundTransparency = 1,
				FontFace = Font.new(
					"rbxasset://fonts/families/Montserrat.json",
					Enum.FontWeight.Heavy,
					Enum.FontStyle.Normal
				),
				Position = UDim2.fromScale(0.265789, 0.178571),
				Size = UDim2.fromScale(0.505895, 0.642857),
				Text = "$60",
				TextColor3 = Color3.fromRGB(255, 193, 59),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2,

				create("UITextSizeConstraint")({
					MaxTextSize = 88,
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 3.2619,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),

	create("Frame")({
		Name = "Hotbar Container",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.500026, 0.983333),
		Size = UDim2.fromScale(0.282031, 0.1),
		ZIndex = 13,

		create("Frame")({
			Name = "Hotbar Slot 01",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.202216, 1),
			ZIndex = 2,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://75462913076534",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.17037),
				Size = UDim2.fromScale(1.47032, 1.49074),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.097717, 0.092593),
				Size = UDim2.fromScale(0.219178, 0.222222),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://94781803337083",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.375, 0.166667),
					Size = UDim2.fromScale(0.27, 0.666667),
					Text = "1",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 26,
					}),
				}),
			}),
		}),

		create("Frame")({
			Name = "Hotbar Slot 02",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.199446, 0.005556),
			Size = UDim2.fromScale(0.202216, 0.988889),
			ZIndex = 3,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://116185397246459",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.177903),
				Size = UDim2.fromScale(1.47032, 1.50749),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.097717, 0.088015),
				Size = UDim2.fromScale(0.219178, 0.224719),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://94781803337083",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.333333, 0.166667),
					Size = UDim2.fromScale(0.36, 0.666667),
					Text = "2",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 26,
					}),
				}),
			}),
		}),

		create("Frame")({
			Name = "Hotbar Slot 03",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.398892, 0.005556),
			Size = UDim2.fromScale(0.202216, 0.988889),
			ZIndex = 4,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://114051206819480",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.177903),
				Size = UDim2.fromScale(1.47032, 1.50749),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.097717, 0.088015),
				Size = UDim2.fromScale(0.219178, 0.224719),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://94781803337083",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.333333, 0.166667),
					Size = UDim2.fromScale(0.36, 0.666667),
					Text = "3",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 26,
					}),
				}),
			}),
		}),

		create("Frame")({
			Name = "Hotbar Slot 04",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.598338, 0.005556),
			Size = UDim2.fromScale(0.202216, 0.988889),
			ZIndex = 5,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://130193220903955",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.177903),
				Size = UDim2.fromScale(1.47032, 1.50749),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.097717, 0.088015),
				Size = UDim2.fromScale(0.219178, 0.224719),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://94781803337083",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.291667, 0.166667),
					Size = UDim2.fromScale(0.45, 0.666667),
					Text = "4",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 26,
					}),
				}),
			}),
		}),

		create("Frame")({
			Name = "Hotbar Slot 05",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.797784, 0.005556),
			Size = UDim2.fromScale(0.202216, 0.988889),
			ZIndex = 6,

			create("ImageLabel")({
				Name = "Art",
				BackgroundTransparency = 1,
				Image = "rbxassetid://108072718401150",
				Interactable = false,
				Position = UDim2.fromScale(-0.235616, -0.177903),
				Size = UDim2.fromScale(1.47032, 1.50749),
			}),

			create("Frame")({
				Name = "Keybind Slot UI",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.097717, 0.088015),
				Size = UDim2.fromScale(0.219178, 0.224719),
				ZIndex = 2,

				create("ImageLabel")({
					Name = "Art",
					BackgroundTransparency = 1,
					Image = "rbxassetid://94781803337083",
					Interactable = false,
					Size = UDim2.fromScale(1, 1),
				}),

				create("TextLabel")({
					Name = "Badge Label",
					BackgroundTransparency = 1,
					FontFace = Font.new(
						"rbxasset://fonts/families/Montserrat.json",
						Enum.FontWeight.Heavy,
						Enum.FontStyle.Normal
					),
					Position = UDim2.fromScale(0.3125, 0.166667),
					Size = UDim2.fromScale(0.405, 0.666667),
					Text = "5",
					TextColor3 = Color3.new(1, 1, 1),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 2,

					create("UITextSizeConstraint")({
						MaxTextSize = 26,
					}),
				}),
			}),
		}),

		create("UIAspectRatioConstraint")({
			AspectRatio = 5.01389,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}),
})
